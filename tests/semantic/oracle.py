"""Compiler-confirmed negative semantic matrix; Python standard library only."""

import argparse
import asyncio
from collections import Counter
import contextlib
from contextlib import asynccontextmanager
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import signal
import subprocess
import sys

from scenarios import load_scenarios


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def canonical(value):
    return json.dumps(value, sort_keys=True)


def compact(diagnostic):
    """Keep the observable contract; optional LSP metadata is not a semantic category."""
    span = diagnostic["range"]
    return {
        "message": diagnostic["message"],
        "severity": diagnostic.get("severity"),
        "range": [span["start"]["line"], span["start"]["character"],
                  span["end"]["line"], span["end"]["character"]],
    }


def discrepancy(expected, actual):
    """A multiset difference preserves duplicate roots, unlike a set or nonempty check."""
    wanted = Counter(map(canonical, expected))
    found = Counter(map(canonical, actual))
    return {"missing": [json.loads(key) for key in sorted(wanted - found)
                        for _ in range((wanted - found)[key])],
            "extra": [json.loads(key) for key in sorted(found - wanted)
                      for _ in range((found - wanted)[key])]}


def desired(step):
    return [{key: value for key, value in item.items() if key != "id"} for item in step["expected"]]


def baseline_delta(case, step, baseline):
    known = baseline.get(case["id"])
    if known is None or step["name"] not in known["steps"]:
        return {"missing": [], "extra": []}
    expectations = {item["id"]: {key: value for key, value in item.items() if key != "id"}
                    for item in step["expected"]}
    return {"missing": sorted((expectations[name] for name in known["missing"]), key=canonical),
            "extra": sorted(known["extra"], key=canonical)}


def check_baseline(case, step, actual, baseline):
    delta = discrepancy(desired(step), actual)
    expected_delta = baseline_delta(case, step, baseline)
    if delta != expected_delta:
        raise AssertionError(f"{case['id']}/{step['name']}: new or unexpectedly fixed discrepancy; "
                             f"expected {expected_delta!r}, observed {delta!r}")
    return delta


def compiler_diagnostics(output):
    output = output.replace("\r\n", "\n")
    return [{"severity": level, "message": message}
            for level, message in re.findall(r"^(error|warning): (.+)$", output, re.MULTILINE)]


def validate(fixtures, baseline):
    cases = {case["id"]: case for case in fixtures}
    if not fixtures or len(cases) != len(fixtures) or set(baseline) - cases.keys():
        raise ValueError("no scenarios, duplicate fixture IDs or orphan baseline entries")
    for name, entry in baseline.items():
        case = cases[name]
        if entry["issue"] != case["issue"]:
            raise ValueError(f"{name}: baseline issue attribution changed")
        if not entry["missing"] and not entry["extra"]:
            raise ValueError(f"{name}: remove fixed baseline entries")
        steps = {step["name"]: step for step in case["steps"]}
        if not entry["steps"] or set(entry["steps"]) - steps.keys():
            raise ValueError(f"{name}: orphan baseline steps")
        for step_name in entry["steps"]:
            step = steps[step_name]
            if set(entry["missing"]) - {item["id"] for item in step["expected"]}:
                raise ValueError(f"{name}/{step_name}: orphan baseline diagnostic IDs")
            for diagnostic in entry["extra"]:
                lines = step["files"][diagnostic["file"]].split("\n")
                a, b, c, d = diagnostic["range"]
                if not (0 <= a <= c < len(lines) and 0 <= b <= len(lines[a].encode("utf-16-le")) // 2
                        and 0 <= d <= len(lines[c].encode("utf-16-le")) // 2 and (a, b) <= (c, d)):
                    raise ValueError(f"{name}: invalid baseline range")
                if not diagnostic["message"] or diagnostic["severity"] not in (1, 2):
                    raise ValueError(f"{name}: invalid baseline diagnostic")


async def kill_tree(process):
    if os.name != "nt":
        # A compiler can exit while a child still holds the output pipes open.
        with contextlib.suppress(ProcessLookupError):
            os.killpg(process.pid, signal.SIGKILL)
    elif process.returncode is None:
        killer = await asyncio.create_subprocess_exec(
            "taskkill", "/PID", str(process.pid), "/T", "/F",
            stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
        await asyncio.wait_for(killer.wait(), 5)
    if process.returncode is None:
        await asyncio.wait_for(process.wait(), 5)


async def command(argv, cwd, env, timeout, logs=None):
    with contextlib.ExitStack() as stack:
        stdout_file = stack.enter_context((logs / "stdout.log").open("wb")) if logs else None
        stderr_file = stack.enter_context((logs / "stderr.log").open("wb")) if logs else None
        process = await asyncio.create_subprocess_exec(
            *map(str, argv), cwd=cwd, env=env, stdout=stdout_file or asyncio.subprocess.PIPE,
            stderr=stderr_file or asyncio.subprocess.PIPE, start_new_session=os.name != "nt")
        try:
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout)
            if logs:
                stdout = (logs / "stdout.log").read_bytes()
                stderr = (logs / "stderr.log").read_bytes()
            return process.returncode, stdout.decode(errors="replace"), stderr.decode(errors="replace")
        finally:
            await kill_tree(process)


class Lsp:
    def __init__(self, process, wire, timeout):
        self.process, self.wire, self.timeout = process, wire, timeout
        self.serial = 0
        self.loading = set()
        self.loaded = False

    async def send(self, **message):
        message = {"jsonrpc": "2.0", **message}
        self.wire.write(json.dumps({"direction": "send", "message": message}) + "\n")
        self.wire.flush()
        body = json.dumps(message).encode()
        self.process.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
        await asyncio.wait_for(self.process.stdin.drain(), self.timeout)

    async def receive(self):
        header = await self.process.stdout.readuntil(b"\r\n\r\n")
        length = next(int(line.split(b":", 1)[1]) for line in header.split(b"\r\n")
                      if line.lower().startswith(b"content-length:"))
        message = json.loads(await self.process.stdout.readexactly(length))
        self.wire.write(json.dumps({"direction": "receive", "message": message}) + "\n")
        self.wire.flush()
        method = message.get("method")
        if method == "$/progress":
            token, value = message["params"]["token"], message["params"]["value"]
            if value.get("title") == "Loading the workspace":
                self.loading.add(token)
            if token in self.loading and value.get("kind") == "end":
                self.loaded = True
        if method and "id" in message:
            if method == "workspace/configuration":
                result = [None] * len(message["params"]["items"])
            elif method in ("window/workDoneProgress/create", "client/registerCapability",
                            "workspace/semanticTokens/refresh", "workspace/diagnostic/refresh"):
                result = None
            else:
                await self.send(id=message["id"], error={"code": -32601, "message": method})
                return message
            await self.send(id=message["id"], result=result)
        return message

    async def call(self, method, params):
        async def request():
            self.serial += 1
            ident = self.serial
            await self.send(id=ident, method=method, params=params)
            while True:
                message = await self.receive()
                if message.get("id") == ident and "method" not in message:
                    if "error" in message:
                        raise RuntimeError(message["error"])
                    return message["result"]
        return await asyncio.wait_for(request(), self.timeout)

    async def wait_loaded(self):
        async def wait():
            while not self.loaded:
                await self.receive()
        await asyncio.wait_for(wait(), self.timeout)

    async def change(self, path, source, version):
        await self.send(method="textDocument/didChange", params={
            "textDocument": {"uri": path.as_uri(), "version": version},
            "contentChanges": [{"text": source}]})

    async def diagnostics(self, path):
        report = await self.call("textDocument/diagnostic", {"textDocument": {"uri": path.as_uri()}})
        if report.get("kind") != "full":
            raise AssertionError(f"expected a full diagnostic report, got {report}")
        return report["items"]


@asynccontextmanager
async def server(binary, sdk, workspace, output, env, timeout, initial):
    with (output / "server.stderr.log").open("wb") as stderr, \
            (output / "server.wire.jsonl").open("w", encoding="utf-8") as wire:
        process = await asyncio.create_subprocess_exec(
            str(binary), cwd=workspace, env=env, stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE, stderr=stderr, start_new_session=os.name != "nt")
        rpc = Lsp(process, wire, timeout)
        try:
            result = await rpc.call("initialize", {
                "processId": os.getpid(), "rootUri": workspace.as_uri(),
                "workspaceFolders": [{"uri": workspace.as_uri(), "name": "audit"}],
                "capabilities": {"window": {"workDoneProgress": True},
                                 "general": {"positionEncodings": ["utf-16"]},
                                 "textDocument": {"diagnostic": {}},
                                 "workspace": {"configuration": True}},
                "initializationOptions": {"cangjieHome": str(sdk)}})
            if result["capabilities"].get("positionEncoding", "utf-16") != "utf-16":
                raise AssertionError("oracle ranges use UTF-16")
            await rpc.send(method="initialized", params={})
            await rpc.wait_loaded()
            for name, source in initial.items():
                path = workspace / name
                await rpc.send(method="textDocument/didOpen", params={"textDocument": {
                    "uri": path.as_uri(), "languageId": "cangjie", "version": 1, "text": source}})
            yield rpc
            await rpc.call("shutdown", None)
            await rpc.send(method="exit", params=None)
            await asyncio.wait_for(process.wait(), 5)
            if process.returncode:
                raise RuntimeError(f"server exited {process.returncode}")
        finally:
            await kill_tree(process)


def prepare_workspace(case, workspace):
    """Materialize explicit package projects for cjls's normal project loader."""
    initial = {}
    packages = {package["name"]: package for package in case["packages"]}
    for package in case["packages"]:
        root = workspace / package["root"]
        (root / "src").mkdir(parents=True)
        manifest = ('[package]\ncjc-version = "1.3.0"\n'
                    f'name = "{package["name"]}"\nversion = "1.0.0"\n'
                    'output-type = "static"\nsrc-dir = "src"\n')
        if package["dependencies"]:
            manifest += "\n[dependencies]\n"
            for dependency in package["dependencies"]:
                relative = Path(os.path.relpath(workspace / packages[dependency]["root"], root)).as_posix()
                manifest += f'{dependency} = {{ path = {json.dumps(relative)} }}\n'
        (root / "cjpm.toml").write_text(manifest, encoding="utf-8")
        for name in case["steps"][0]["files"]:
            if PurePosixPath(name).parent == PurePosixPath(package["root"]) / "src":
                initial[name] = f"package {package['name']}\n"
                (workspace / name).write_text(initial[name], encoding="utf-8")
    if len(packages) > 1:
        members = [package["root"] for package in packages.values()]
        (workspace / "cjpm.toml").write_text(
            f"[workspace]\nmembers = {json.dumps(members)}\n", encoding="utf-8")
    return initial


async def compile_step(case, step, sdk, output, env, timeout):
    folder = output / "steps" / step["name"]
    for name, source in step["files"].items():
        path = folder / "workspace" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source, encoding="utf-8")
    executable = sdk / "bin" / ("cjc.exe" if os.name == "nt" else "cjc")
    results, dependencies = [], {}
    for package in case["packages"]:
        logs = folder / "compiler" / package["name"]
        logs.mkdir(parents=True)
        source_dir = folder / "workspace" / package["root"] / "src"
        argv = [str(executable), "--diagnostic-format", "noColor", "-Woff", "unused",
                "--output-type", "staticlib", "-p", str(source_dir),
                "-o", str(logs / f"lib{package['name']}.a")]
        # Include the transitive closure, without leaking unrelated packages into lookup.
        imports = set(package["dependencies"])
        for dependency in package["dependencies"]:
            imports.update(dependencies[dependency])
        dependencies[package["name"]] = imports
        for dependency in sorted(imports):
            library = folder / "compiler" / dependency
            argv.extend(["--import-path", str(library), "-L", str(library), f"-l{dependency}"])
        write_json(logs / "command.json", {"argv": argv, "cwd": str(folder), "timeout": timeout})
        status, stdout, stderr = await command(argv, folder, env, timeout, logs=logs)
        diagnostics = compiler_diagnostics(stderr + stdout)
        result = {"package": package["name"], "status": status, "diagnostics": diagnostics,
                  "command": argv, "artifacts": str(logs.relative_to(output))}
        expected = step["compiler"][package["name"]]
        rejected = any(item["severity"] == "error" for item in expected)
        if status != (1 if rejected else 0) or diagnostics != expected:
            result["failure"] = f"compiler expected {expected!r}, exit {int(rejected)}"
        results.append(result)
    return results


async def apply_step(rpc, workspace, previous, step, version):
    """Apply only actual changes, including document and filesystem lifecycle events."""
    for name in sorted(previous.keys() - step["files"].keys()):
        path = workspace / name
        await rpc.send(method="textDocument/didClose", params={"textDocument": {"uri": path.as_uri()}})
        path.unlink()
        await rpc.send(method="workspace/didChangeWatchedFiles",
                       params={"changes": [{"uri": path.as_uri(), "type": 3}]})
    for name, source in step["files"].items():
        path = workspace / name
        if name not in previous:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(source, encoding="utf-8")
            await rpc.send(method="workspace/didChangeWatchedFiles",
                           params={"changes": [{"uri": path.as_uri(), "type": 1}]})
            await rpc.send(method="textDocument/didOpen", params={"textDocument": {
                "uri": path.as_uri(), "languageId": "cangjie", "version": version, "text": source}})
        elif source != previous[name]:
            await rpc.change(path, source, version)


async def run_case(case, baseline, binary, sdk, output, env, timeout, report):
    output.mkdir(parents=True)
    workspace = output / "workspace"
    previous = prepare_workspace(case, workspace)
    item = {"id": case["id"], "issue": case["issue"], "phases": []}
    report["cases"].append(item)
    compiled = {}
    async with server(binary, sdk, workspace, output, env, timeout, previous) as rpc:
        for version, step in enumerate(case["steps"], 2):
            observed = {"phase": step["name"], "changed_files": [], "deleted_files": []}
            item["phases"].append(observed)
            key = canonical({"files": step["files"], "compiler": step["compiler"]})
            if key in compiled:
                observed["compiler_reused_from"] = compiled[key][0]
                observed["compiler"] = compiled[key][1]
            else:
                observed["compiler"] = await compile_step(case, step, sdk, output, env, timeout)
                compiled[key] = (step["name"], observed["compiler"])
            for result in observed["compiler"]:
                if "failure" in result:
                    report["failures"].append(f"{case['id']}/{step['name']}/{result['package']}: {result['failure']}")
            observed["changed_files"] = [name for name, text in step["files"].items()
                                         if previous.get(name) != text]
            observed["deleted_files"] = sorted(previous.keys() - step["files"].keys())
            await apply_step(rpc, workspace, previous, step, version)
            previous = step["files"]
            actual = []
            observed["diagnostics"] = {}
            for name in sorted(step["files"]):
                diagnostics = await rpc.diagnostics(workspace / name)
                observed["diagnostics"][name] = diagnostics
                actual.extend({"file": name, **compact(d)} for d in diagnostics)
            try:
                observed["discrepancy"] = check_baseline(case, step, actual, baseline)
            except AssertionError as error:
                report["failures"].append(str(error))


def git(*args):
    return subprocess.check_output(["git", *args], cwd=REPO, text=True).strip()


async def run(args):
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {"schema": 2, "status": "failed", "cases": [], "failures": [], "skips": []}
    try:
        fixtures, baseline = load_scenarios(HERE / "cases"), read_json(HERE / "baseline.json")
        validate(fixtures, baseline)
        if args.case:
            fixtures = [case for case in fixtures if case["id"] in args.case]
            if set(args.case) - {case["id"] for case in fixtures}:
                raise ValueError("unknown --case ID")
        selected_sdk = args.sdk or os.environ.get("CANGJIE_HOME")
        if not selected_sdk:
            raise ValueError("select the pinned SDK with --sdk or CANGJIE_HOME")
        sdk = Path(selected_sdk).resolve()
        executable = sdk / "bin" / ("cjc.exe" if os.name == "nt" else "cjc")
        binary = args.server.resolve()
        env = {**os.environ, "CANGJIE_HOME": str(sdk), "cjHeapSize": "2GB"}
        # SDK discovery is explicit; no wrapper can silently select a different compiler.
        status, version, stderr = await command([executable, "--version"], REPO, env, args.timeout)
        pin = (REPO / ".cangjie-version").read_text().strip()
        report["metadata"] = {
            "revision": git("rev-parse", "HEAD"), "worktree_status": git("status", "--short"),
            "diff_sha256": hashlib.sha256(git("diff", "HEAD").encode()).hexdigest(),
            "server": str(binary), "server_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
            "sdk": str(sdk), "sdk_pin": pin, "compiler_version": version + stderr,
            "platform": platform.platform(), "machine": platform.machine(),
            "python": sys.version, "command": sys.argv, "timeout_seconds": args.timeout,
            "scenarios_sha256": hashlib.sha256("".join(
                path.relative_to(HERE).as_posix() + "\0" + path.read_text(encoding="utf-8")
                for path in sorted((HERE / "cases").rglob("*.test"))).encode()).hexdigest(),
            "baseline_sha256": hashlib.sha256((HERE / "baseline.json").read_bytes()).hexdigest(),
        }
        if status or f"Compiler: {pin} (" not in version:
            raise ValueError(f"compiler does not match repository SDK pin {pin}: {version}{stderr}")
        for case in fixtures:
            applicable = case.get("platforms")
            if applicable and sys.platform not in applicable:
                report["skips"].append({"id": case["id"], "reason": case["skip_reason"],
                                        "platform": sys.platform, "sdk": pin})
                continue
            try:
                await run_case(case, baseline, binary, sdk, output / "cases" / case["id"],
                               env, args.timeout, report)
            except Exception as error:
                report["failures"].append(f"{case['id']}: {type(error).__name__}: {error}")
            print(f"{case['id']}: checked", flush=True)
            write_json(output / "report.json", report)
        report["status"] = "passed" if not report["failures"] else "failed"
    except Exception as error:
        report["failures"].append(f"{type(error).__name__}: {error}")
    finally:
        write_json(output / "report.json", report)
    print(f"{report['status']}: {len(report['cases'])} cases, {len(report['skips'])} skips, "
          f"{len(report['failures'])} failures; {output / 'report.json'}")
    for failure in report["failures"]:
        print(failure, file=sys.stderr)
    return 0 if report["status"] == "passed" else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", help="SDK root (defaults to explicit CANGJIE_HOME; must match pin)")
    parser.add_argument("--server", type=Path, default=REPO / "target/release/bin" /
                        ("cjls.exe" if os.name == "nt" else "cjls"))
    parser.add_argument("--output", type=Path, default=REPO / "target/semantic-oracle")
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--case", action="append", help="fixture ID; repeat to select focused cases")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    sys.exit(main())
