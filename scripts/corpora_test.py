"""Release source corpora must match the window without moving the nightly corpus."""

import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "corpora_fetch", Path(__file__).resolve().parents[1] / "tests/corpora/fetch.py")
corpora = importlib.util.module_from_spec(spec)
spec.loader.exec_module(corpora)


class ReleaseSourcesTest(unittest.TestCase):
    def test_release_layouts_and_commits_leave_nightly_unchanged(self):
        nightly = corpora.SUITES["cangjie_runtime"]
        window = {
            "lts": {"version": "1.0.5", "runtime": {"commit": "a" * 40, "std": "std/libs/std"}},
            "sts": {"version": "1.2.0", "runtime": {"commit": "b" * 40, "std": "stdlib/libs/std"}},
        }
        with patch.object(corpora, "fetch") as fetch, patch.object(corpora.json, "load", return_value=window):
            lts = Path(corpora.release_sources("1.0.5"))
            sts = Path(corpora.release_sources("1.2.0"))
        self.assertEqual(lts.parts[-4:], ("cangjie_runtime-1.0.5", "std", "libs", "std"))
        self.assertEqual(sts.parts[-4:], ("cangjie_runtime-1.2.0", "stdlib", "libs", "std"))
        self.assertEqual([call.args[0] for call in fetch.call_args_list],
                         ["cangjie_runtime-1.0.5", "cangjie_runtime-1.2.0"])
        for version in ("1.0.5", "1.2.0"):
            self.assertRegex(corpora.SUITES[f"cangjie_runtime-{version}"][1], r"^[0-9a-f]{40}$")
        self.assertEqual(corpora.SUITES["cangjie_runtime"], nightly)
