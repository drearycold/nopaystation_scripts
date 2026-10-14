"""Offline regression tests; run with python3 -m unittest discover -s tests."""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
GAME_ID = "PCSG00025"
DLC_IDS = ["BGM000000000SET1", "BGM000000000SET2", "BGM000000000SET3"]


class DlcDownloadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="nps-dlc-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()
        mock = self.bin_dir / "dlc_tool.sh"
        shutil.copyfile(REPO / "tests/fixtures/dlc_tool.sh", mock)
        mock.chmod(0o755)
        for tool in ["wget", "pkg2zip", "t7z", "file", "mktorrent"]:
            (self.bin_dir / tool).symlink_to(mock)
        (self.bin_dir / "nps_dlc.sh").symlink_to(REPO / "nps_dlc.sh")
        self.tsv = self.root / "PSV_DLCS.tsv"
        self.log = self.root / "downloads.log"
        self.output = self.root / "output with spaces"
        self.env = dict(os.environ)
        for name in ["TITLE_ID", "DESTDIR"]:
            self.env.pop(name, None)
        self.env.update({
            "PATH": f"{self.bin_dir}:{os.environ['PATH']}",
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "NPS_DOWNLOAD_DIR": str(self.root / "download"),
            "NPS_EXTRACT_DIR": str(self.root / "extract"),
            "NPS_OUTPUT_DIR": str(self.output),
            "NPS_CHECKSUM_MISMATCH_ACTION": "no",
            "TEST_DOWNLOAD_LOG": str(self.log),
            "TEST_FAIL_ARCHIVE": "0",
        })

    def write_tsv(self, *, missing_first=False, content_ids=True):
        rows = []
        for index, dlc_id in enumerate(DLC_IDS):
            link = f"https://example.invalid/{dlc_id}.pkg"
            if missing_first and index == 0:
                link = "MISSING"
            content = f"JP0747-{GAME_ID}_00-{dlc_id}" if content_ids else ""
            checksum = hashlib.sha256(f"{dlc_id}.pkg".encode()).hexdigest()
            rows.append("\t".join([
                GAME_ID, "JP", "Test DLC", link, "KEY", content,
                "2026-01-01", "1", checksum,
            ]))
        self.tsv.write_text("\r\n".join(rows) + "\r\n")

    def archive_path(self, dlc_id, *, output=None, game_id=GAME_ID):
        base = output if output is not None else self.output
        return base / f"{GAME_ID}_dlc" / (
            f"Test DLC [{game_id}] [NTSC-J] [DLC-{dlc_id}].7z"
        )

    def seed_archive(self, dlc_id, *, output=None, game_id=GAME_ID, data="archive"):
        path = self.archive_path(dlc_id, output=output, game_id=game_id)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)
        return path

    def run_dlc(self):
        return subprocess.run(
            ["sh", str(REPO / "nps_dlc.sh"), str(self.tsv), GAME_ID],
            env=self.env, cwd=self.root, capture_output=True, text=True, timeout=10,
        )

    def downloaded_ids(self):
        if not self.log.exists():
            return []
        return [line.rsplit("/", 1)[-1].removesuffix(".pkg")
                for line in self.log.read_text().splitlines()]

    def assert_temp_clean(self):
        for name in ["download", "extract"]:
            self.assertEqual(list((self.root / name).iterdir()), [])

    def test_partial_download_then_rerun(self):
        self.write_tsv()
        existing = self.seed_archive(DLC_IDS[0])
        original_stat = existing.stat()
        result = self.run_dlc()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(self.downloaded_ids(), DLC_IDS[1:])
        self.assertEqual(existing.stat().st_mtime_ns, original_stat.st_mtime_ns)
        self.assertTrue(all(self.archive_path(dlc_id).exists() for dlc_id in DLC_IDS))
        self.assert_temp_clean()
        result = self.run_dlc()
        self.assertEqual(result.returncode, 5, result.stderr + result.stdout)
        self.assertEqual(self.downloaded_ids(), DLC_IDS[1:])

    def test_same_dlc_id_for_other_game_is_not_skipped(self):
        self.write_tsv()
        self.seed_archive(DLC_IDS[0], game_id="PCSG99999")
        result = self.run_dlc()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(self.downloaded_ids(), DLC_IDS)

    def test_missing_entry_does_not_stop_later_downloads(self):
        self.write_tsv(missing_first=True)
        result = self.run_dlc()
        self.assertEqual(result.returncode, 4, result.stderr + result.stdout)
        self.assertEqual(self.downloaded_ids(), DLC_IDS[1:])
        self.assert_temp_clean()

    def test_without_content_id_skips_exact_existing_name(self):
        self.write_tsv(content_ids=False)
        for dlc_id in DLC_IDS:
            self.seed_archive(dlc_id)
        self.env["TEST_FAIL_ARCHIVE"] = "1"
        result = self.run_dlc()
        self.assertEqual(result.returncode, 5, result.stderr + result.stdout)
        self.assertEqual(self.downloaded_ids(), DLC_IDS)
        self.assert_temp_clean()

    def test_invalid_existing_archive_is_preserved(self):
        self.write_tsv()
        existing = self.seed_archive(DLC_IDS[0], data="invalid")
        result = self.run_dlc()
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        self.assertEqual(existing.read_text(), "invalid")
        self.assertEqual(self.downloaded_ids(), [])

    def test_failed_archive_does_not_report_success(self):
        self.write_tsv()
        self.env["TEST_FAIL_ARCHIVE"] = "1"
        result = self.run_dlc()
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        self.assertEqual(self.downloaded_ids(), DLC_IDS[:1])

    def test_no_matching_game_returns_no_dlc(self):
        self.tsv.write_text("PCSG99999\tJP\tOther game\n")
        result = self.run_dlc()
        self.assertEqual(result.returncode, 2, result.stderr + result.stdout)
        self.assertEqual(self.downloaded_ids(), [])

    def test_region_dlc_command_downloads_only_missing_items(self):
        self.write_tsv()
        (self.root / "PSV_GAMES.tsv").write_text(f"{GAME_ID}\tJP\tTest Game\n")
        collection = self.output / "Sony - PlayStation Vita (NTSC-J) - (dlc)"
        self.seed_archive(DLC_IDS[0], output=collection)
        for _ in range(2):
            result = subprocess.run(
                ["sh", str(REPO / "nps_region.sh"), "-r", "JP", "-d", ".", "-t", "dlc"],
                env=self.env, cwd=self.root, capture_output=True, text=True, timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertEqual(self.downloaded_ids(), DLC_IDS[1:])
        self.assert_temp_clean()


if __name__ == "__main__":
    unittest.main()
