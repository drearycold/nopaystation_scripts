"""Offline update resume and output-directory regression tests."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
GAME_ID = "PCSG00025"
VERSIONS = ["1.00", "1.01", "1.02"]


class UpdateDownloadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="nps-patch-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        tool = bin_dir / "patch_tool.sh"
        shutil.copyfile(REPO / "tests/fixtures/patch_tool.sh", tool)
        tool.chmod(0o755)
        for name in ["pyNPU.py", "wget", "pkg2zip", "t7z", "file", "mktorrent"]:
            (bin_dir / name).symlink_to(tool)
        for name in ["nps_game.sh", "nps_dlc.sh"]:
            (bin_dir / name).symlink_to(tool)
        (bin_dir / "nps_update.sh").symlink_to(REPO / "nps_update.sh")
        self.metadata = self.root / "metadata.tsv"
        self.metadata.write_text("".join(
            f"0{version}\thttps://example.invalid/{version}.pkg\n"
            for version in VERSIONS
        ))
        self.output = self.root / "output with spaces"
        self.destination = self.output / f"Test Game [{GAME_ID}] [NTSC-J]_update"
        self.log = self.root / "downloads.log"
        self.env = dict(os.environ)
        self.env.pop("DESTDIR", None)
        self.env.update({
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "NPS_DOWNLOAD_DIR": str(self.root / "download"),
            "NPS_EXTRACT_DIR": str(self.root / "extract"),
            "NPS_OUTPUT_DIR": str(self.output),
            "TEST_METADATA_FILE": str(self.metadata),
            "TEST_METADATA_STATUS": "0",
            "TEST_DOWNLOAD_LOG": str(self.log),
            "TEST_FAIL_ARCHIVE": "0",
        })

    def seed_archive(self, version, *, folder=None, game_id=GAME_ID, data="archive"):
        folder = folder if folder is not None else self.destination
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / f"Test Game [{game_id}] [NTSC-J] [PATCH] [v{version}].7z"
        path.write_text(data)
        return path

    def run_update(self, *, all_versions=True):
        command = ["sh", str(REPO / "nps_update.sh")]
        if all_versions:
            command.append("-a")
        return subprocess.run(
            command + [GAME_ID], env=self.env, cwd=self.root,
            capture_output=True, text=True, timeout=10,
        )

    def downloads(self):
        if not self.log.exists():
            return []
        return [line.rsplit("/", 1)[-1].removesuffix(".pkg")
                for line in self.log.read_text().splitlines()]

    def assert_temp_clean(self):
        for name in ["download", "extract"]:
            self.assertEqual(list((self.root / name).iterdir()), [])

    def test_all_versions_on_fresh_run_and_rerun(self):
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(self.downloads(), VERSIONS)
        self.assertEqual(len(list(self.destination.glob("*.7z"))), 3)
        result = self.run_update()
        self.assertEqual(result.returncode, 5, result.stderr + result.stdout)
        self.assertEqual(self.downloads(), VERSIONS)
        self.assertFalse(any(path.is_dir() for path in self.destination.iterdir()))
        self.assert_temp_clean()

    def test_partial_versions_are_completed(self):
        first = self.seed_archive(VERSIONS[0])
        self.seed_archive(VERSIONS[2])
        original = first.stat().st_mtime_ns
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(self.downloads(), VERSIONS[1:2])
        self.assertEqual(first.stat().st_mtime_ns, original)
        self.assert_temp_clean()

    def test_old_version_does_not_skip_latest(self):
        self.seed_archive(VERSIONS[0])
        result = self.run_update(all_versions=False)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(self.downloads(), VERSIONS[2:])

    def test_explicit_destdir_is_reused(self):
        self.env["DESTDIR"] = "Custom Game Folder"
        folder = self.output / "Custom Game Folder_update"
        self.seed_archive(VERSIONS[0], folder=folder)
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(self.downloads(), VERSIONS[1:])
        self.assertEqual(len(list(folder.glob("*.7z"))), 3)
        self.assertFalse(self.destination.exists())

    def test_legacy_and_renamed_folders_are_both_checked(self):
        legacy = self.output / f"{GAME_ID}_update"
        self.seed_archive(VERSIONS[0], folder=legacy)
        self.seed_archive(VERSIONS[1])
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(self.downloads(), VERSIONS[2:])
        self.assertTrue(legacy.is_dir())
        self.assertFalse((self.destination / legacy.name).exists())

    def test_legacy_folder_alone_is_reused(self):
        legacy = self.output / f"{GAME_ID}_update"
        self.seed_archive(VERSIONS[0], folder=legacy)
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(self.downloads(), VERSIONS[1:])
        self.assertEqual(len(list(legacy.glob("*.7z"))), 3)
        self.assertFalse(self.destination.exists())

    def test_other_game_patch_is_not_skipped(self):
        self.seed_archive(VERSIONS[2], game_id="PCSG99999")
        result = self.run_update(all_versions=False)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(self.downloads(), VERSIONS[2:])

    def test_invalid_archive_is_preserved(self):
        archive = self.seed_archive(VERSIONS[0], data="invalid")
        result = self.run_update()
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        self.assertEqual(archive.read_text(), "invalid")
        self.assertEqual(self.downloads(), [])

    def test_metadata_failure_and_no_updates(self):
        for status in [1, 2]:
            self.env["TEST_METADATA_STATUS"] = str(status)
            result = self.run_update()
            self.assertEqual(result.returncode, status, result.stderr + result.stdout)
            self.assertEqual(self.downloads(), [])

    def test_failed_compression_returns_error(self):
        self.env["TEST_FAIL_ARCHIVE"] = "1"
        result = self.run_update()
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
        self.assertEqual(self.downloads(), VERSIONS[:1])

    def test_region_all_flag_before_other_options(self):
        (self.root / "PSV_GAMES.tsv").write_text(f"{GAME_ID}\tJP\tTest Game\n")
        for _ in range(2):
            result = subprocess.run(
                ["sh", str(REPO / "nps_region.sh"), "-a", "-r", "JP", "-d", ".", "-t", "update"],
                env=self.env, cwd=self.root, capture_output=True, text=True, timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertEqual(self.downloads(), VERSIONS)
        self.assert_temp_clean()

    def test_bundle_all_flag_before_other_options(self):
        for name in ["PSV_GAMES.tsv", "PSV_DLCS.tsv", "PSV_UPDATES.tsv"]:
            (self.root / name).touch()
        result = subprocess.run(
            ["sh", str(REPO / "nps_bundle.sh"), "-a", "-t", GAME_ID, "-d", "."],
            env=self.env, cwd=self.root, capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(self.downloads(), VERSIONS)
        self.assertEqual(len(list(self.destination.glob("*.7z"))), 3)
        self.assert_temp_clean()


if __name__ == "__main__":
    unittest.main()
