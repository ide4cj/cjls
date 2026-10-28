"""Compiler-confirmed negative semantic matrix; Python standard library only."""

import argparse
import asyncio
from collections import Counter
import contextlib
from contextlib import asynccontextmanager
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import signal
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
EMPTY = "package audit\n"


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


def check_baseline(case, actual, baseline):
    delta = discrepancy(case["expected"], actual)
    known = baseline.get(case["id"], {"issue": case["issue"], "missing": [], "extra": []})
    if known["issue"] != case["issue"]:
        raise ValueError(f"{case['id']}: baseline issue attribution changed")
    expected_delta = {key: sorted(known[key], key=canonical) for key in ("missing", "extra")}
    if delta != expected_delta:
        raise AssertionError(f"{case['id']}: new or unexpectedly fixed discrepancy; "
                             f"expected {expected_delta!r}, observed {delta!r}")
    return delta


def compiler_diagnostics(output):
    return [{"severity": level, "message": message}
            for level, message in re.findall(r"^(error|warning): (.+)$", output, re.MULTILINE)]


def validate(fixtures, baseline):
    ids = [case["id"] for case in fixtures]
    if len(set(ids)) != len(ids) or set(baseline) - set(ids):
        raise ValueError("duplicate fixture IDs or orphan baseline entries")
    for case in fixtures:
        if not isinstance(case["issue"], int) or case["issue"] <= 0:
            raise ValueError(f"{case['id']}: missing issue attribution")
        if "platforms" in case and not case.get("skip_reason"):
            raise ValueError(f"{case['id']}: platform applicability needs a skip reason")
        for diagnostic in case["expected"]:
            start_line, start_col, end_line, end_col = diagnostic["range"]
            lines = case["source"].splitlines()
            if not (0 <= start_line <= end_line < len(lines)
                    and 0 <= start_col <= len(lines[start_line])
                    and 0 <= end_col <= len(lines[end_line])
                    and (start_line, start_col) <= (end_line, end_col)):
                raise ValueError(f"{case['id']}: invalid expected source range")
            if not diagnostic["message"] or diagnostic["severity"] not in (1, 2):
                raise ValueError(f"{case['id']}: missing category/severity")
        if any(d["severity"] == "error" for d in case["compiler"]) and "fixed" not in case:
            raise ValueError(f"{case['id']}: rejected fixture needs a corrected control")
    for name, entry in baseline.items():
        if not entry["missing"] and not entry["extra"]:
            raise ValueError(f"{name}: remove fixed baseline entries")


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
async def server(binary, sdk, workspace, output, env, timeout):
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
            for name in ("main.cj", "declarations.cj"):
                path = workspace / "src" / name
                await rpc.send(method="textDocument/didOpen", params={"textDocument": {
                    "uri": path.as_uri(), "languageId": "cangjie", "version": 1, "text": EMPTY}})
            yield rpc
            await rpc.call("shutdown", None)
            await rpc.send(method="exit", params=None)
            await asyncio.wait_for(process.wait(), 5)
            if process.returncode:
                raise RuntimeError(f"server exited {process.returncode}")
        finally:
            await kill_tree(process)


async def compile_case(case, phase, sdk, output, env, timeout):
    folder = output / "cases" / case["id"] / phase
    folder.mkdir(parents=True)
    source = case["fixed"] if phase == "fixed" else case["source"]
    declarations = case.get("fixed_declarations", case.get("declarations", EMPTY)) \
        if phase == "fixed" else case.get("declarations", EMPTY)
    (folder / "main.cj").write_text(source, encoding="utf-8")
    (folder / "declarations.cj").write_text(declarations, encoding="utf-8")
    executable = sdk / "bin" / ("cjc.exe" if os.name == "nt" else "cjc")
    argv = [str(executable), "--diagnostic-format", "noColor", "-Woff", "unused",
            "--output-type", "staticlib", "main.cj", "declarations.cj", "-o", "libaudit.a"]
    write_json(folder / "command.json", {"argv": argv, "cwd": str(folder), "timeout": timeout})
    status, stdout, stderr = await command(argv, folder, env, timeout, logs=folder)
    diagnostics = compiler_diagnostics(stderr + stdout)
    result = {"status": status, "diagnostics": diagnostics, "command": argv,
              "artifacts": str(folder.relative_to(output))}
    expected = [] if phase == "fixed" else case["compiler"]
    rejected = any(item["severity"] == "error" for item in expected)
    # A crash or warning-only exit must never count as the expected semantic rejection.
    if status != (1 if rejected else 0) or diagnostics != expected:
        result["failure"] = f"compiler expected {expected!r}, exit {int(rejected)}"
    return result


def git(*args):
    return subprocess.check_output(["git", *args], cwd=REPO, text=True).strip()


async def run(args):
    fixtures, baseline = read_json(HERE / "fixtures.json"), read_json(HERE / "baseline.json")
    validate(fixtures, baseline)
    if args.case:
        fixtures = [case for case in fixtures if case["id"] in args.case]
        if set(args.case) - {case["id"] for case in fixtures}:
            raise ValueError("unknown --case ID")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {"schema": 1, "status": "failed", "cases": [], "failures": [], "skips": []}
    try:
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
            "fixtures_sha256": hashlib.sha256((HERE / "fixtures.json").read_bytes()).hexdigest(),
            "baseline_sha256": hashlib.sha256((HERE / "baseline.json").read_bytes()).hexdigest(),
        }
        if status or f"Compiler: {pin} (" not in version:
            raise ValueError(f"compiler does not match repository SDK pin {pin}: {version}{stderr}")
        workspace = output / "workspace"
        (workspace / "src").mkdir(parents=True)
        (workspace / "cjpm.toml").write_text(
            '[package]\ncjc-version = "1.3.0"\nname = "audit"\nversion = "1.0.0"\n'
            'output-type = "static"\nsrc-dir = "src"\n', encoding="utf-8")
        for name in ("main.cj", "declarations.cj"):
            (workspace / "src" / name).write_text(EMPTY, encoding="utf-8")
        async with server(binary, sdk, workspace, output, env, args.timeout) as rpc:
            version = 1
            for case in fixtures:
                applicable = case.get("platforms")
                if applicable and sys.platform not in applicable:
                    report["skips"].append({"id": case["id"], "reason": case["skip_reason"],
                                            "platform": sys.platform, "sdk": pin})
                    continue
                item = {"id": case["id"], "issue": case["issue"], "phases": []}
                report["cases"].append(item)
                for phase in (["broken", "fixed", "restored"] if "fixed" in case else ["control"]):
                    version += 1
                    observed = {"phase": phase}
                    item["phases"].append(observed)
                    if phase != "restored":
                        observed["compiler"] = await compile_case(case, phase, sdk, output, env, args.timeout)
                        if "failure" in observed["compiler"]:
                            report["failures"].append(f"{case['id']}/{phase}: {observed['compiler']['failure']}")
                    source = case["fixed"] if phase == "fixed" else case["source"]
                    declarations = case.get("fixed_declarations", case.get("declarations", EMPTY)) \
                        if phase == "fixed" else case.get("declarations", EMPTY)
                    # Change the declaration first; the pull is ordered after both input updates.
                    await rpc.change(workspace / "src/declarations.cj", declarations, version)
                    if phase in ("broken", "control") or case.get("fixed") != case["source"]:
                        await rpc.change(workspace / "src/main.cj", source, version)
                    observed["diagnostics"] = await rpc.diagnostics(workspace / "src/main.cj")
                    observed["declaration_diagnostics"] = await rpc.diagnostics(workspace / "src/declarations.cj")
                    try:
                        actual = list(map(compact, observed["diagnostics"]))
                        if phase == "fixed":
                            if actual or observed["declaration_diagnostics"]:
                                raise AssertionError(f"{case['id']}: corrected control has diagnostics")
                        else:
                            observed["discrepancy"] = check_baseline(case, actual, baseline)
                            if observed["declaration_diagnostics"]:
                                raise AssertionError(f"{case['id']}: unexpected declaration diagnostics")
                    except AssertionError as error:
                        report["failures"].append(str(error))
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
