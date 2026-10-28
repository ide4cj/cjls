"""Offline contracts, including planted regressions in the diagnostic result."""

import asyncio
import copy
import os
from pathlib import Path
import sys
import tempfile
import unittest

from oracle import HERE, check_baseline, command, compiler_diagnostics, read_json, validate


def failure(operation):
    try:
        operation()
    except Exception as error:
        return error
    return None


class OracleTest(unittest.TestCase):
    def setUp(self):
        self.fixtures = read_json(HERE / "fixtures.json")
        self.baseline = read_json(HERE / "baseline.json")
        self.exact = next(case for case in self.fixtures if case["id"] == "return_wrong_type")

    def test_fixture_contract(self):
        # arrange
        fixtures, baseline = self.fixtures, self.baseline

        # act
        error = failure(lambda: validate(fixtures, baseline))

        # assert
        self.assertIsNone(error)

    def test_unchanged_exact_diagnostic(self):
        # arrange
        actual = self.exact["expected"]

        # act
        delta = check_baseline(self.exact, actual, self.baseline)

        # assert
        self.assertEqual(delta, {"missing": [], "extra": []})

    def test_planted_missing_diagnostic_fails(self):
        # arrange
        actual = []

        # act
        error = failure(lambda: check_baseline(self.exact, actual, self.baseline))

        # assert
        self.assertIsInstance(error, AssertionError)
        self.assertIn("new or unexpectedly fixed", str(error))

    def test_planted_duplicate_diagnostic_fails(self):
        # arrange
        actual = self.exact["expected"] * 2

        # act
        error = failure(lambda: check_baseline(self.exact, actual, self.baseline))

        # assert
        self.assertIsInstance(error, AssertionError)
        self.assertIn("new or unexpectedly fixed", str(error))

    def test_wrong_category_severity_and_range_each_fail(self):
        # arrange
        mutations = {"message": "expected a declaration", "severity": 2, "range": [1, 1, 1, 2]}
        for key, value in mutations.items():
            with self.subTest(field=key):
                actual = copy.deepcopy(self.exact["expected"])
                actual[0][key] = value

                # act
                error = failure(lambda: check_baseline(self.exact, actual, self.baseline))

                # assert
                self.assertIsInstance(error, AssertionError)

    def test_unexpectedly_fixed_baseline_fails(self):
        # arrange
        case = next(case for case in self.fixtures if case["id"] == "field_missing_class")
        actual = case["expected"]

        # act
        error = failure(lambda: check_baseline(case, actual, self.baseline))

        # assert
        self.assertIsInstance(error, AssertionError)
        self.assertIn("unexpectedly fixed", str(error))

    def test_extra_duplicate_baseline_cannot_silently_disappear(self):
        # arrange
        case = next(case for case in self.fixtures if case["id"] == "control_mismatch")

        # act
        error = failure(lambda: check_baseline(case, case["expected"], self.baseline))

        # assert
        self.assertIsInstance(error, AssertionError)
        self.assertIn("unexpectedly fixed", str(error))

    def test_warning_is_not_an_error(self):
        # arrange
        output = "warning: magnitude too large\n ==> main.cj:2:1:\n1 warning generated.\n"

        # act
        diagnostics = compiler_diagnostics(output)

        # assert
        self.assertEqual(diagnostics, [{"severity": "warning", "message": "magnitude too large"}])

    def test_orphan_baseline_fails(self):
        # arrange
        baseline = {**self.baseline, "deleted_fixture": {"issue": 528, "missing": [], "extra": []}}

        # act
        error = failure(lambda: validate(self.fixtures, baseline))

        # assert
        self.assertIsInstance(error, ValueError)
        self.assertIn("orphan", str(error))


class ProcessTest(unittest.IsolatedAsyncioTestCase):
    async def test_timeout_kills_children_and_keeps_compiler_logs(self):
        # arrange: the child's OS lock is released only when that process exits.
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            (path / "child.lock").write_bytes(b"x")
            lock = (
                "import os; file = open('child.lock', 'r+b'); "
                "exec(\"if os.name == 'nt':\\n import msvcrt; "
                "msvcrt.locking(file.fileno(), msvcrt.LK_LOCK, 1)\\n"
                "else:\\n import fcntl; fcntl.flock(file, fcntl.LOCK_EX)\"); "
            )
            child = lock + "import time; print(os.getpid(), flush=True); time.sleep(60)"
            parent = (
                "import subprocess, sys, time; "
                f"subprocess.Popen([sys.executable, '-c', {child!r}]); time.sleep(60)"
            )
            error = None
            child_pid = None
            cleaned = False
            try:
                # act
                try:
                    await command([sys.executable, "-c", parent], path, os.environ, 2, logs=path)
                except asyncio.TimeoutError as caught:
                    error = caught
                stdout = (path / "stdout.log").read_text()
                child_pid = int(stdout.strip())
                status, _, _ = await command(
                    [sys.executable, "-c", lock], path, os.environ, 3)
                cleaned = status == 0

                # assert
                self.assertIsInstance(error, asyncio.TimeoutError)
                self.assertEqual(status, 0)
            finally:
                # A failing cleanup regression must not leave its own child behind.
                if not cleaned and child_pid is not None:
                    try:
                        os.kill(child_pid, 9)
                    except OSError:
                        pass


if __name__ == "__main__":
    unittest.main()
