"""Check versioned metadata output using a mocked Sony XML response."""

from contextlib import redirect_stdout
import io
from pathlib import Path
import runpy
from unittest import mock
import unittest


REPO = Path(__file__).resolve().parents[1]
XML = b'''<titlepatch status="alive"><tag>
<package version="01.00" url="https://example.invalid/old.pkg"/>
<package version="01.02" url="https://example.invalid/latest.pkg">
<hybrid_package url="https://example.invalid/hybrid.pkg"/>
</package></tag></titlepatch>'''


class UpdateMetadataTests(unittest.TestCase):
    def output(self, *options):
        response = mock.Mock(status_code=200, content=XML)
        stream = io.StringIO()
        argv = ["pyNPU.py", "--link", "--title-id", "PCSG00025", *options]
        with mock.patch("sys.argv", argv), mock.patch("requests.get", return_value=response), redirect_stdout(stream):
            runpy.run_path(str(REPO / "pyNPU.py"), run_name="__main__")
        return stream.getvalue().splitlines()

    def test_latest_bare_url_is_unchanged(self):
        self.assertEqual(self.output(), ["https://example.invalid/hybrid.pkg"])

    def test_all_bare_urls_are_unchanged(self):
        self.assertEqual(self.output("--all"), [
            "https://example.invalid/old.pkg", "https://example.invalid/hybrid.pkg",
        ])

    def test_latest_with_version_uses_parent_package_version(self):
        self.assertEqual(self.output("--with-version"), [
            "01.02\thttps://example.invalid/hybrid.pkg",
        ])

    def test_all_with_version(self):
        self.assertEqual(self.output("--all", "--with-version"), [
            "01.00\thttps://example.invalid/old.pkg",
            "01.02\thttps://example.invalid/hybrid.pkg",
        ])


if __name__ == "__main__":
    unittest.main()
