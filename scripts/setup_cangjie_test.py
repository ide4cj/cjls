"""Installer pinning must hold before release or mirror archives can be unpacked."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "setup_cangjie", Path(__file__).resolve().parents[1] / ".github/actions/setup-cangjie/setup.py"
)
setup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(setup)


class InstallerTests(unittest.TestCase):
    def test_unpinned_archive_is_never_requested(self):
        # arrange
        with patch.object(setup, "pinned", return_value={}), patch.object(setup, "download") as download:
            # act / assert
            with self.assertRaisesRegex(SystemExit, "is not in .cangjie-sha256"):
                setup.fetch("1.2.0", "sdk.tar.gz", "unused")
            download.assert_not_called()

    def test_release_uses_its_explicit_url(self):
        # arrange
        with patch.object(setup, "releases", return_value={"1.2.0": {"sdk": "https://release/sdk"}}):
            # act
            release = setup.urls("1.2.0", "sdk")
            nightly = setup.urls("nightly", "sdk")
            # assert
            self.assertEqual(release, ["https://release/sdk"])
            self.assertEqual(nightly, [f"{url}/nightly/sdk" for url in setup.MIRRORS])

    def test_wrong_digest_is_removed(self):
        # arrange
        with tempfile.TemporaryDirectory() as directory:
            archive = str(Path(directory) / "sdk.tar.gz")
            with patch.object(setup, "pinned", return_value={"sdk": "expected"}), \
                    patch.object(setup, "urls", return_value=["https://release/sdk"]), \
                    patch.object(setup, "download", return_value="wrong"):
                # act / assert
                with self.assertRaisesRegex(SystemExit, "no source served"):
                    setup.fetch("1.2.0", "sdk", archive)
                self.assertFalse(Path(archive).exists())

    def test_pinning_preserves_window_and_retires_old_nightly(self):
        # arrange
        releases = {"1.2.0": {"release-sdk": "https://release/sdk"}}
        with tempfile.TemporaryDirectory() as directory:
            sums = Path(directory) / "sums"
            sums.write_text("release-sha  release-sdk\nold-sha  old-nightly\n")
            with patch.object(setup, "SUMS", str(sums)), patch.object(setup, "releases", return_value=releases), \
                    patch.object(setup, "archives", return_value=["new-nightly"]), \
                    patch.object(setup, "download", return_value="new-sha"):
                # act
                setup.pin("nightly")
                actual = setup.pinned()
                # assert
                self.assertEqual(actual, {"release-sdk": "release-sha", "new-nightly": "new-sha"})

    def test_pinning_release_retains_nightly_and_other_releases(self):
        # arrange
        with tempfile.TemporaryDirectory() as directory:
            sums = Path(directory) / "sums"
            sums.write_text("nightly-sha  nightly\nother-sha  other-sdk\nold-sha  release-sdk\n")
            with patch.object(setup, "SUMS", str(sums)), \
                    patch.object(setup, "releases", return_value={"1.2.0": {"release-sdk": "https://release/sdk"}}), \
                    patch.object(setup, "archives", return_value=["release-sdk"]), \
                    patch.object(setup, "download", return_value="release-sha"):
                # act
                setup.pin("1.2.0")
                actual = setup.pinned()
                # assert
                self.assertEqual(actual, {
                    "nightly": "nightly-sha", "other-sdk": "other-sha", "release-sdk": "release-sha",
                })

    def test_window_has_each_supported_archive(self):
        # arrange
        expected_channels = {"lts", "sts"}
        # act
        releases = setup.releases()
        sums = setup.pinned()
        with open(setup.WINDOW) as window:
            channels = set(json.load(window))
        expected = {
            version: {name for asset, ext, _ in setup.PLATFORMS.values()
                      for name in setup.archives(asset, ext, version)}
            for version in releases
        }
        # assert
        self.assertEqual(channels, expected_channels)
        for version, urls in releases.items():
            self.assertEqual(set(urls), expected[version])
            for name, url in urls.items():
                self.assertIn(name, url)
                self.assertRegex(sums.get(name, ""), r"^[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main()
