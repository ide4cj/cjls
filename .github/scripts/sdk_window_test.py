import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import sdk_window


class SdkWindowTest(unittest.TestCase):
    def test_matrix_tracks_versions_by_channel(self):
        # arrange
        with tempfile.TemporaryDirectory() as directory:
            window = Path(directory) / "window"
            window.write_text(json.dumps({"sts": {"version": "2.1.0"},
                                          "lts": {"version": "2.0.1"}}))
            # act
            result = sdk_window.matrix(window)

            # assert
            self.assertEqual(result, {"include": [
                {"channel": "lts", "version": "2.0.1"},
                {"channel": "sts", "version": "2.1.0"}]})

    @patch.dict("os.environ", {"LD_LIBRARY_PATH": "/pin/runtime"})
    @patch("sdk_window.subprocess.run")
    def test_failed_package_does_not_hide_other_packages(self, run):
        # arrange
        run.return_value.returncode = 1

        # act
        result = sdk_window.test(Path.cwd(), Path("binaries"))

        # assert
        self.assertEqual(result, 1)
        self.assertEqual([call.args[0][0] for call in run.call_args_list],
                         [f"binaries/{name}" for name in sdk_window.PACKAGES])
        for call in run.call_args_list:
            self.assertEqual(call.kwargs["env"]["CANGJIE_HOME"], str(Path.cwd()))
            self.assertIn("--timeout-each=2m", call.args[0])
            self.assertEqual(call.kwargs["env"]["LD_LIBRARY_PATH"], "/pin/runtime")

    @patch("sdk_window.subprocess.run", side_effect=FileNotFoundError)
    def test_missing_binary_fails(self, _run):
        # arrange
        sdk = Path.cwd()
        binaries = Path("binaries")

        # act / assert
        with self.assertRaises(FileNotFoundError):
            sdk_window.test(sdk, binaries)
