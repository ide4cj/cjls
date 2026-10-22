"""Check probe cleanup and stack attribution without requiring a macOS runner."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "probe", Path(__file__).with_name("runtime-factor-probe.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class RuntimeProbeTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.previous = Path.cwd()
        os.chdir(self.scratch.name)
        self.addCleanup(os.chdir, self.previous)

    def test_records_exit_status_and_actual_limits(self):
        command = [sys.executable, "-c", "print('child output'); raise SystemExit(7)"]
        self.assertEqual(probe.run_once("failure", command, 5), 7)
        row, = json.loads(probe.RESULTS.read_text())
        self.assertEqual(row["command"], command)
        self.assertEqual(row["timeout_seconds"], 5)
        self.assertGreater(row["log_bytes"], 0)
        self.assertIn("child output", (probe.LOGS / "failure.txt").read_text())

    def test_timeout_kills_descendants_after_diagnostics(self):
        child = "import time; from pathlib import Path; time.sleep(1); Path('survived').touch()"
        parent = f"import subprocess, sys, time; subprocess.Popen([sys.executable, '-c', {child!r}]); time.sleep(30)"
        with patch.object(probe, "diagnostics", wraps=probe.diagnostics) as capture:
            status = probe.run_once("hang", [sys.executable, "-c", parent], 0.2)
        self.assertEqual(status, "timeout")
        capture.assert_called_once()
        subprocess.run([sys.executable, "-c", "import time; time.sleep(1.1)"], check=True)
        self.assertFalse(Path("survived").exists())
        self.assertTrue(list(probe.LOGS.glob("hang-*.processes.txt")))

    def test_samples_launcher_and_children_but_not_other_groups(self):
        probe.LOGS.mkdir()
        snapshot = subprocess.CompletedProcess([], 0, stdout=(
            "100 1 100 01:00 00:01 0.0 1024 cjpm test\n"
            "101 100 100 01:00 00:01 0.0 1024 test-binary\n"
            "200 1 200 01:00 00:01 0.0 1024 unrelated\n"), stderr="")
        with patch.object(probe.sys, "platform", "darwin"), patch.object(
                probe.subprocess, "run", return_value=snapshot) as run:
            probe.diagnostics("full-1", 100, 600)
        self.assertEqual([call.args[0] for call in run.call_args_list[1:]],
                         [["sample", "100", "1", "1"], ["sample", "101", "1", "1"]])

    def test_sampling_failure_preserves_diagnostics(self):
        probe.LOGS.mkdir()
        snapshot = subprocess.CompletedProcess([], 0,
            stdout="100 1 100 01:00 00:01 0.0 1024 cjpm test\n", stderr="")
        with patch.object(probe.sys, "platform", "darwin"), patch.object(
                probe.subprocess, "run", side_effect=[snapshot, OSError("sample missing")]):
            probe.diagnostics("full-1", 100, 600)
        self.assertIn("sample missing", (probe.LOGS / "full-1-600s-pid-100.sample.txt").read_text())

    def test_timeout_overrides_reach_gate_and_full_commands(self):
        with patch.dict(os.environ, {"PROBE_GATE_TIMEOUT": "123", "PROBE_FULL_TIMEOUT": "456"}), patch.object(
                probe, "run_once", return_value=0) as run:
            with patch.object(sys, "argv", ["probe", "gate", "6", "6"]):
                self.assertTrue(probe.main())
            self.assertEqual(run.call_args.args[2], 123)
            with patch.object(sys, "argv", ["probe", "full"]):
                self.assertTrue(probe.main())
            self.assertEqual(run.call_args.args[2], 456)


if __name__ == "__main__":
    unittest.main()
