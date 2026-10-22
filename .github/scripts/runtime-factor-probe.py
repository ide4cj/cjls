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
        "--timeout-each=2m", "--target-dir", "target/test"]


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
    (LOGS / "manifest-changes.patch").write_bytes(subprocess.check_output(["git", "diff"]))
    config = {"variant": os.environ["PROBE_VARIANT"], "optimization": level,
              "workers": os.environ["PROBE_WORKERS"],
              "sdk": Path(".cangjie-version").read_text().strip()}
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
    if env.get("PROBE_WORKERS"):
        env["cjProcessorNum"] = env["PROBE_WORKERS"]
    else:
        env.pop("cjProcessorNum", None)
    print(json.dumps({"event": "start", "run": name, "timeout": timeout,
                      "cjProcessorNum": env.get("cjProcessorNum", "default")}), flush=True)
    with (LOGS / f"{name}.txt").open("w") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                   env=env, start_new_session=True)
        status = None
        while status is None:
            remaining = timeout - (time.monotonic() - started)
            if remaining <= 0:
                # Kill the test and its macro servers, not only their cjpm parent.
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                status = "timeout"
                break
            try:
                status = process.wait(timeout=min(30, remaining))
            except subprocess.TimeoutExpired:
                print(json.dumps({"event": "running", "run": name,
                                  "seconds": round(time.monotonic() - started),
                                  "log_bytes": (LOGS / f"{name}.txt").stat().st_size}), flush=True)
    row = {"run": name, "status": status, "seconds": round(time.monotonic() - started, 2)}
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
    expected = {"full-1", *(f"gate-{n}" for n in range(1, 11))}
    return {r["run"] for r in rows} == expected and all(r["status"] == 0 for r in rows)


def main():
    mode = sys.argv[1]
    if mode == "prepare":
        prepare()
    elif mode == "audit":
        audit()
    elif mode == "gate":
        statuses = [run_once(f"gate-{n}", BASE + ["--filter=ServedDiagnosticsGateTest.*"], 300)
                    for n in range(int(sys.argv[2]), int(sys.argv[3]) + 1)]
        return all(status == 0 for status in statuses)
    elif mode == "full":
        return run_once("full-1", BASE, 600) == 0
    elif mode == "report":
        return report()
    else:
        raise ValueError(mode)
    return True


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
