"""Run bounded macOS GC probes, retaining partial results and real compiler flags."""

import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import tomllib


LOGS = Path("probe-logs")
RESULTS = LOGS / "results.json"
BASE = ["cjpm", "test", "--skip-build", "--no-progress",
        f"--timeout-each={os.environ.get('PROBE_TIMEOUT_EACH', '10m')}",
        "--target-dir", "target/test"]


def diagnostics(name, pid, elapsed):
    """Preserve native stacks before killing a slow invocation's process group."""
    prefix = LOGS / f"{name}-{int(elapsed)}s"
    deadline = time.monotonic() + 20
    try:
        snapshot = subprocess.run(
            ["ps", "-axo", "pid=,ppid=,pgid=,etime=,time=,%cpu=,rss=,command="],
            capture_output=True, text=True, timeout=10)
        prefix.with_suffix(".processes.txt").write_text(snapshot.stdout + snapshot.stderr)
        if sys.platform != "darwin":
            return
        members = []
        for line in snapshot.stdout.splitlines():
            fields = line.split(None, 7)
            if len(fields) == 8 and fields[2] == str(pid):
                members.append(int(fields[0]))
        # The launcher may buffer all output while a child hangs. Sample children
        # as well as cjpm; a launcher-only stack cannot locate a runtime stall.
        for member in members:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                Path(f"{prefix}.diagnostic-error.txt").write_text(
                    "Stack collection exceeded its 20-second budget; some processes were not sampled.")
                break
            with Path(f"{prefix}-pid-{member}.sample.txt").open("w") as out:
                try:
                    subprocess.run(["sample", str(member), "1", "1"],
                                   stdout=out, stderr=subprocess.STDOUT, timeout=min(5, remaining))
                except (OSError, subprocess.TimeoutExpired) as error:
                    out.write(f"\nSample unavailable: {error}\n")
    except (OSError, subprocess.TimeoutExpired) as error:
        Path(f"{prefix}.diagnostic-error.txt").write_text(str(error))


def configure_test_environment(workers, stack):
    assert workers in {"", "1"}
    assert stack in {"", "8MB"}
    path = Path("cjpm.toml")
    text = path.read_text()
    for name, value in (("cjProcessorNum", workers), ("cjStackSize", stack)):
        if not value:
            continue
        text, count = re.subn(
            r'(\[profile.test.env\]\n)',
            rf'\1{name} = {{ value = "{value}", splice-type = "replace" }}\n', text)
        assert count == 1, "no unique test environment section"
    path.write_text(text)


def prepare():
    LOGS.mkdir(exist_ok=True)
    assert not Path("target/test").exists(), "factor builds must start without objects"
    level = os.environ["PROBE_OPTIMIZATION"]
    assert level in {"0", "1", "2"}
    workspace = tomllib.loads(Path("cjpm.toml").read_text())["workspace"]
    for member in workspace["members"]:
        path = Path(member) / "cjpm.toml"
        # Preserve the CJMP workaround in O2 control and one-worker builds.
        selected = "1" if member == "modules/platform" and level == "2" else level
        text, count = re.subn(
            r'(\[target\.aarch64-apple-darwin\.release\]\ncompile-option = ")-O[012](")',
            rf'\g<1>-O{selected}\2', path.read_text())
        assert count == 1, f"no unique Darwin optimization setting in {path}"
        path.write_text(text)
    workers = os.environ["PROBE_WORKERS"]
    stack = os.environ.get("PROBE_STACK_SIZE", "")
    configure_test_environment(workers, stack)
    (LOGS / "manifest-changes.patch").write_bytes(subprocess.check_output(["git", "diff"]))
    config = {"variant": os.environ["PROBE_VARIANT"], "optimization": level,
              "workers": workers, "worker_configuration": "profile.test.env",
              "stack_size": stack or "default", "stack_configuration": "profile.test.env",
              "sdk": Path(".cangjie-version").read_text().strip(),
              "gate_timeout_seconds": int(os.environ.get("PROBE_GATE_TIMEOUT", "900")),
              "full_timeout_seconds": int(os.environ.get("PROBE_FULL_TIMEOUT", "1800")),
              "timeout_each": os.environ.get("PROBE_TIMEOUT_EACH", "10m")}
    (LOGS / "configuration.json").write_text(json.dumps(config, indent=2))
    shim = Path(os.environ["RUNNER_TEMP"]) / "factor-shim"
    shim.mkdir()
    source = Path(".github/scripts/trace-probe-cjc.py").resolve()
    source.chmod(0o755)
    (shim / "cjc").symlink_to(source)
    with open(os.environ["GITHUB_PATH"], "a") as out:
        out.write(str(shim) + "\n")
    with open(os.environ["GITHUB_ENV"], "a") as out:
        out.write(f"PROBE_CJC_TRACE={(LOGS / 'compiler').resolve()}\n")


def audit():
    level = os.environ["PROBE_OPTIMIZATION"]
    found = []
    for path in sorted((LOGS / "compiler").glob("*.json")):
        call = json.loads(path.read_text())
        flags = [a for a in call["args"] if re.fullmatch(r"-O[012]", a)]
        if not flags:
            continue  # Dependency scans and build.cj are not module code generation.
        platform = Path(call["cwd"]).name == "platform" or any(
            re.search(r"(?:^|/)modules/platform(?:/src(?:/|$)|$)", arg) for arg in call["args"])
        selected = "1" if level == "2" and platform else level
        assert flags[-1] == f"-O{selected}", call
        found.append({"cwd": call["cwd"], "optimization": flags[-1], "trace": path.name})
    assert found, "no compiler optimization flags captured"
    (LOGS / "optimization-audit.json").write_text(json.dumps(found, indent=2))
    print(f"Audited {len(found)} compiler invocations", flush=True)


def run_once(name, command, timeout):
    LOGS.mkdir(exist_ok=True)
    started = time.monotonic()
    env = dict(os.environ)
    # Limit test binaries through cjpm's profile, leaving the package manager's
    # own scheduler unchanged; globally setting this variable can stall cjpm.
    env.pop("cjProcessorNum", None)
    # Compare test/runtime stack settings without changing the cjpm launcher.
    env.pop("cjStackSize", None)
    print(json.dumps({"event": "start", "run": name, "timeout": timeout,
                      "test_workers": env.get("PROBE_WORKERS") or "default",
                      "test_stack": env.get("PROBE_STACK_SIZE") or "default",
                      "cjpm_workers": "default"}), flush=True)
    with (LOGS / f"{name}.txt").open("w") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                   env=env, start_new_session=True)
        status = None
        next_snapshot = 60
        while status is None:
            elapsed = time.monotonic() - started
            remaining = timeout - elapsed
            if remaining <= 0:
                diagnostics(name, process.pid, elapsed)
                # Kill the test and its macro servers, not only their cjpm parent.
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass  # The process can exit during native stack collection.
                process.wait()
                status = "timeout"
                break
            if elapsed >= next_snapshot:
                diagnostics(name, process.pid, elapsed)
                next_snapshot = (int(elapsed) // 300 + 1) * 300
                continue
            try:
                status = process.wait(timeout=min(30, remaining))
            except subprocess.TimeoutExpired:
                print(json.dumps({"event": "running", "run": name,
                                  "seconds": round(time.monotonic() - started),
                                  "log_bytes": (LOGS / f"{name}.txt").stat().st_size}), flush=True)
    row = {"run": name, "status": status, "seconds": round(time.monotonic() - started, 2),
           "timeout_seconds": timeout, "command": command,
           "log_bytes": (LOGS / f"{name}.txt").stat().st_size}
    rows = json.loads(RESULTS.read_text()) if RESULTS.exists() else []
    assert all(r["run"] != name for r in rows), f"duplicate repetition {name}"
    rows.append(row)
    RESULTS.write_text(json.dumps(rows, indent=2))
    print(json.dumps(row), flush=True)
    return status


def report():
    rows = json.loads(RESULTS.read_text()) if RESULTS.exists() else []
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as out:
        out.write("| Run | Exit status | Seconds |\n|---|---|---|\n")
        for row in rows:
            out.write(f"| {row['run']} | {row['status']} | {row['seconds']} |\n")
        if len(rows) == 5 and all(row["status"] == "timeout" for row in rows):
            out.write("\nStopped after five timeouts; later repetitions and the full suite were not run.\n")
    expected = {"full-1", *(f"gate-{n}" for n in range(1, 11))}
    return {r["run"] for r in rows} == expected and all(r["status"] == 0 for r in rows)


def main():
    mode = sys.argv[1]
    if mode == "prepare":
        prepare()
    elif mode == "audit":
        audit()
    elif mode == "gate":
        statuses = [run_once(f"gate-{n}", BASE + ["--filter=ServedDiagnosticsGateTest.*"],
                             int(os.environ.get("PROBE_GATE_TIMEOUT", "900")))
                    for n in range(int(sys.argv[2]), int(sys.argv[3]) + 1)]
        if sys.argv[2:] == ["1", "5"] and "GITHUB_OUTPUT" in os.environ:
            # Repeating a wholly timed-out screening batch adds no completed cases.
            proceed = not all(status == "timeout" for status in statuses)
            with open(os.environ["GITHUB_OUTPUT"], "a") as out:
                out.write(f"proceed={str(proceed).lower()}\n")
        return all(status == 0 for status in statuses)
    elif mode == "full":
        return run_once("full-1", BASE, int(os.environ.get("PROBE_FULL_TIMEOUT", "1800"))) == 0
    elif mode == "report":
        return report()
    else:
        raise ValueError(mode)
    return True


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
