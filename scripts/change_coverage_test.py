"""Regression checks for coverage selection and report provenance."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("change_coverage", Path(__file__).with_name("change_coverage.py"))
coverage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coverage)


class CoverageTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        old = Path.cwd()
        os.chdir(self.temp.name)
        self.addCleanup(os.chdir, old)
        self.git("init", "-q")
        self.write("modules/example/src/a.cj", "baseline")
        self.git("add", ".")
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-qm", "baseline")
        self.write("modules/example/src/a.cj", "changed")
        self.real_run = subprocess.run
        self.file = {"filepath": "modules/example/src/a.cj", "hitLines": [1], "totalLines": 2}

    def git(self, *args):
        return subprocess.check_output(["git", *args], stderr=subprocess.DEVNULL)

    def write(self, name, content):
        path = Path(name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def generate(self, mutation=None):
        def command(args, **kwargs):
            if args[0] == "git":
                return self.real_run(args, **kwargs)
            if args[0] == "cjcov":
                self.write(str(coverage.REPORT), json.dumps({"fileLists": [self.file]}))
                self.write("coverage/index.html", "report")
                if mutation:
                    mutation()
        with patch.object(coverage.subprocess, "run", side_effect=command) as run:
            with contextlib.redirect_stdout(io.StringIO()):
                coverage.generate()
        return run

    def inspect(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = coverage.inspect("HEAD")
        return result, output.getvalue()

    def test_policy_is_shared_with_ci(self):
        # arrange
        included = "modules/example/src/a.cj"
        excluded = ["modules/example/src/a_test.cj", "modules/cjls/src/lsp_types/foo.cj",
                    "modules/loupe/src/fixture/foo.cj", "modules/calca/src/macros/foo.cj", "other/a.cj"]
        files = [self.file] + [{"filepath": name, "hitLines": [1, 2], "totalLines": 3} for name in excluded]

        # act
        is_included = coverage.policy.included(included.replace("/", "\\"))
        excluded_results = [coverage.policy.included(name) for name in excluded]
        counts = coverage.policy.counts({"fileLists": files})

        # assert
        self.assertTrue(is_included)
        self.assertEqual(excluded_results, [False] * len(excluded))
        self.assertEqual(counts, (1, 2))

    def test_missing_provenance_rejected(self):
        # arrange
        self.write(str(coverage.REPORT), json.dumps({"fileLists": [self.file]}))

        # act
        with self.assertRaises(ValueError) as raised:
            self.inspect()

        # assert
        self.assertRegex(str(raised.exception), "missing")

    def test_fresh_report_includes_working_edits_and_distinguishes_missing_excluded(self):
        # arrange
        self.write("modules/example/src/new.cj", "new")
        self.write("modules/example/src/new_test.cj", "test")

        # act
        run = self.generate()
        result, output = self.inspect()

        # assert
        test_command = next(call.args[0] for call in run.call_args_list if call.args[0][0] == "cjpm")
        self.assertIn("--exclude-tags", test_command)
        self.assertEqual(result, 1)
        self.assertIn("a.cj: 1/2", output)
        self.assertIn("new.cj: missing from coverage report", output)
        self.assertIn("new_test.cj: excluded by CI coverage policy", output)

    def test_renamed_source_is_selected_at_new_path(self):
        # arrange
        self.git("mv", self.file["filepath"], "modules/example/src/renamed.cj")

        # act
        changed = coverage.changed("HEAD")

        # assert
        self.assertIn("modules/example/src/renamed.cj", changed)

    def test_complete_report_succeeds(self):
        # arrange
        self.generate()

        # act
        result, output = self.inspect()

        # assert
        self.assertEqual(result, 0)
        self.assertIn("a.cj: 1/2", output)

    def test_missing_html_is_reported(self):
        # arrange
        self.generate()
        Path("coverage/index.html").unlink()

        # act
        with self.assertRaises(ValueError) as raised:
            self.inspect()

        # assert
        self.assertRegex(str(raised.exception), "missing coverage/index.html")

    def test_malformed_generation_has_no_provenance(self):
        # arrange
        malformed = '{"fileLists": [1]}'

        # act
        with self.assertRaises(ValueError) as raised:
            self.generate(lambda: coverage.REPORT.write_text(malformed))
        has_stamp = coverage.STAMP.exists()

        # assert
        self.assertRegex(str(raised.exception), "malformed coverage report")
        self.assertFalse(has_stamp)

    def test_invalid_counts_cannot_receive_provenance(self):
        # arrange
        cases = [(True, [1]), (-1, []), (0, [1]), (1, [1, 2])]
        for total, hits in cases:
            with self.subTest(total=total, hits=hits):
                # arrange
                self.file.update(totalLines=total, hitLines=hits)

                # act
                with self.assertRaises(ValueError) as raised:
                    self.generate()
                has_stamp = coverage.STAMP.exists()

                # assert
                self.assertRegex(str(raised.exception), "malformed coverage report")
                self.assertFalse(has_stamp)

    def test_duplicate_paths_cannot_hide_a_file_entry(self):
        # arrange
        duplicate = dict(self.file, filepath=self.file["filepath"].replace("/", "\\"), hitLines=[])
        report = {"fileLists": [self.file, duplicate]}

        # act
        with self.assertRaises(ValueError) as raised:
            self.generate(lambda: coverage.REPORT.write_text(json.dumps(report)))
        has_stamp = coverage.STAMP.exists()

        # assert
        self.assertRegex(str(raised.exception), "duplicate coverage path")
        self.assertFalse(has_stamp)

    def test_source_changes_make_report_stale_even_if_mtime_restored(self):
        # arrange
        self.generate()
        source = Path(self.file["filepath"])
        stat = source.stat()
        source.write_text("another change")
        os.utime(source, ns=(stat.st_atime_ns, stat.st_mtime_ns))

        # act
        with self.assertRaises(ValueError) as raised:
            self.inspect()

        # assert
        self.assertRegex(str(raised.exception), "stale")

    def test_report_replacement_is_rejected(self):
        # arrange
        self.generate()
        coverage.REPORT.write_text('{"fileLists": []}')

        # act
        with self.assertRaises(ValueError) as raised:
            self.inspect()

        # assert
        self.assertRegex(str(raised.exception), "stale")

    def test_inputs_changing_during_generation_are_not_blessed(self):
        # arrange
        def edit_source():
            self.write(self.file["filepath"], "edited during tests")

        # act
        with self.assertRaises(ValueError) as raised:
            self.generate(edit_source)
        has_stamp = coverage.STAMP.exists()

        # assert
        self.assertRegex(str(raised.exception), "inputs changed")
        self.assertFalse(has_stamp)

    def test_failed_run_invalidates_old_artifacts(self):
        # arrange
        self.generate()

        def failure(args, **kwargs):
            if args[0] == "git":
                return self.real_run(args, **kwargs)
            raise subprocess.CalledProcessError(1, "cjpm")

        # act
        with patch.object(coverage.subprocess, "run", side_effect=failure):
            with self.assertRaises(subprocess.CalledProcessError) as raised:
                coverage.generate()
        has_stamp = coverage.STAMP.exists()
        has_report = coverage.REPORT.exists()

        # assert
        self.assertEqual(raised.exception.returncode, 1)
        self.assertFalse(has_stamp)
        self.assertFalse(has_report)


if __name__ == "__main__":
    unittest.main()
