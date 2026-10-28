"""Offline contracts, including planted regressions in the diagnostic result."""

import asyncio
import copy
import os
from pathlib import Path
import sys
import tempfile
import unittest

from oracle import HERE, check_known, command, compiler_diagnostics, desired, validate
from scenarios import load_scenarios


def failure(operation):
    try:
        operation()
    except Exception as error:
        return error
    return None


class OracleTest(unittest.TestCase):
    def setUp(self):
        self.fixtures = load_scenarios(HERE / "cases")
        self.exact = next(case for case in self.fixtures if case["id"] == "return_wrong_type")
        self.step = self.exact["steps"][0]

    def test_fixture_contract(self):
        # arrange
        fixtures = self.fixtures

        # act
        error = failure(lambda: validate(fixtures))

        # assert
        self.assertIsNone(error)

    def test_unchanged_exact_diagnostic(self):
        # arrange
        actual = desired(self.step)

        # act
        delta = check_known(self.exact, self.step, actual)

        # assert
        self.assertEqual(delta, {"missing": [], "extra": []})

    def test_planted_missing_diagnostic_fails(self):
        # arrange
        actual = []

        # act
        error = failure(lambda: check_known(self.exact, self.step, actual))

        # assert
        self.assertIsInstance(error, AssertionError)
        self.assertIn("new or unexpectedly fixed", str(error))

    def test_planted_duplicate_diagnostic_fails(self):
        # arrange
        actual = desired(self.step) * 2

        # act
        error = failure(lambda: check_known(self.exact, self.step, actual))

        # assert
        self.assertIsInstance(error, AssertionError)
        self.assertIn("new or unexpectedly fixed", str(error))

    def test_wrong_category_severity_and_range_each_fail(self):
        # arrange
        mutations = {"message": "expected a declaration", "severity": 2, "range": [1, 1, 1, 2],
                     "file": "src/other.cj"}
        for key, value in mutations.items():
            with self.subTest(field=key):
                actual = copy.deepcopy(desired(self.step))
                actual[0][key] = value

                # act
                error = failure(lambda: check_known(self.exact, self.step, actual))

                # assert
                self.assertIsInstance(error, AssertionError)

    def test_unexpectedly_fixed_known_difference_fails(self):
        # arrange
        case = next(case for case in self.fixtures if case["id"] == "field_missing_class")
        actual = desired(case["steps"][0])

        # act
        error = failure(lambda: check_known(case, case["steps"][0], actual))

        # assert
        self.assertIsInstance(error, AssertionError)
        self.assertIn("unexpectedly fixed", str(error))

    def test_known_extra_duplicate_cannot_silently_disappear(self):
        # arrange
        case = next(case for case in self.fixtures if case["id"] == "control_mismatch")

        # act
        error = failure(lambda: check_known(case, case["steps"][0], desired(case["steps"][0])))

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

    def test_windows_compiler_headlines_have_the_same_contract(self):
        # arrange: subprocess logs are retained as bytes, including Windows CRLF.
        output = "error: mismatched types\r\n ==> main.cj:2:1:\r\nwarning: magnitude too large\r\n"

        # act
        diagnostics = compiler_diagnostics(output)

        # assert
        self.assertEqual(diagnostics, [
            {"severity": "error", "message": "mismatched types"},
            {"severity": "warning", "message": "magnitude too large"},
        ])

    def test_duplicate_scenario_fails(self):
        # arrange
        fixtures = self.fixtures + [self.exact]

        # act
        error = failure(lambda: validate(fixtures))

        # assert
        self.assertIsInstance(error, ValueError)
        self.assertIn("duplicate", str(error))

    def test_known_missing_does_not_hide_an_unrelated_extra(self):
        # arrange
        case = next(case for case in self.fixtures if case["id"] == "field_missing_class")
        step = case["steps"][0]
        actual = [{**desired(step)[0], "message": "unrelated regression"}]

        # act
        error = failure(lambda: check_known(case, step, actual))

        # assert
        self.assertIsInstance(error, AssertionError)

    def test_known_extra_keeps_its_own_range_and_multiplicity(self):
        # arrange
        case = next(case for case in self.fixtures if case["id"] == "control_mismatch")
        step = case["steps"][0]
        extra = {key: value for key, value in step["known"]["extra"][0].items() if key != "issue"}
        actual = desired(step) + [extra]

        # act
        delta = check_known(case, step, actual)
        duplicate_error = failure(lambda: check_known(case, step, actual + [extra]))

        # assert
        self.assertNotEqual(extra["range"], desired(step)[0]["range"])
        self.assertEqual(delta["extra"], [extra])
        self.assertIsInstance(duplicate_error, AssertionError)


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
