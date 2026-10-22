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
        read_fd, write_fd = os.pipe()
        self.addCleanup(os.close, read_fd)
        self.addCleanup(os.close, write_fd)
        child = "import signal; print('ready', flush=True); signal.pause()"
        parent = (f"import os, signal, subprocess, sys; child = subprocess.Popen("
                  f"[sys.executable, '-c', {child!r}], stdout=subprocess.PIPE); "
                  f"child.stdout.readline(); os.write({write_fd}, str(child.pid).encode()); signal.pause()")
        popen = subprocess.Popen
        launched = []

        def start_ready(*args, **kwargs):
            process = popen(*args, **kwargs, pass_fds=(write_fd,))
            launched.append(process)
            # The descendant is blocked before the invocation's timer can fire.
            self.assertTrue(os.read(read_fd, 64).isdigit())
            return process

        with patch.object(probe.subprocess, "Popen", side_effect=start_ready), patch.object(
                probe, "diagnostics") as capture:
            status = probe.run_once("hang", [sys.executable, "-c", parent], 0.001)
        self.assertEqual(status, "timeout")
        capture.assert_called_once()
        snapshot = subprocess.check_output(["ps", "-axo", "pgid=,state="], text=True)
        for line in snapshot.splitlines():
            group, state = line.split()
            if group == str(launched[0].pid):
                self.assertTrue(state.startswith("Z"), line)

    def test_retains_process_table_without_native_sampler(self):
        probe.LOGS.mkdir()
        with patch.object(probe.sys, "platform", "linux"):
            probe.diagnostics("full-1", os.getpid(), 60)
        self.assertTrue((probe.LOGS / "full-1-60s.processes.txt").read_text())

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
