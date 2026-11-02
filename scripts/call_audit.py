#!/usr/bin/env python3
"""Run the tracked-function audit through the real cjmcp runPython binding."""
import argparse
from collections import Counter
import hashlib
import os
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--summary", type=Path, help="Also save per-root outcomes and gap counts")
    parser.add_argument("--limit", type=int, default=10000)
    args = parser.parse_args()
    implementation = Path(__file__).resolve().parents[1] / "scripts/call_audit_lib.py"
    code = implementation.read_text() + f"\nresult = audit(workspace, limit={args.limit!r})\n"
    messages = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "call-audit", "version": "1"}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "runPython", "arguments": {"code": code}}}]
    process = subprocess.run([str(args.binary.resolve()), "--dir", str(args.workspace.resolve())],
                             input="".join(json.dumps(message) + "\n" for message in messages),
                             stdout=subprocess.PIPE, text=True, check=True)
    replies = [json.loads(line) for line in process.stdout.splitlines()]
    response = next(reply for reply in replies if reply.get("id") == 2)
    payload = response["result"]["structuredContent"]
    if payload["error"]:
        raise RuntimeError(payload["error"])
    report = payload["result"]
    def git_value(*arguments):
        check = subprocess.run(["git", "-C", str(args.workspace), *arguments],
                               capture_output=True, text=True)
        return check.stdout.strip() if check.returncode == 0 else None
    report["provenance"] = {
        "workspace_commit": git_value("rev-parse", "HEAD"),
        "workspace_tracked_changes": git_value("status", "--porcelain", "--untracked-files=no"),
        "binary_sha256": hashlib.sha256(args.binary.read_bytes()).hexdigest(),
        "analysis_sdk": os.environ.get("CANGJIE_HOME"),
        "python_library": os.environ.get("PYTHON_DYNLIB"),
    }
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    if args.summary:
        examples = {}
        for row in report["reports"]:
            for gap in row["gaps"]:
                examples.setdefault(gap["reason"], gap)
        summary = {key: value for key, value in report.items() if key != "reports"}
        summary["full_report_sha256"] = hashlib.sha256(args.output.read_bytes()).hexdigest()
        summary["gap_examples"] = examples
        summary["reports"] = [
            {**{key: value for key, value in row.items() if key != "gaps"},
             "gap_counts": dict(sorted(Counter(gap["reason"] for gap in row["gaps"]).items()))}
            for row in report["reports"]
        ]
        text = json.dumps(summary, ensure_ascii=False, indent=2)
        text = text.replace(str(args.workspace.resolve()) + "/", "")
        args.summary.write_text(text + "\n")
    print(json.dumps({"tracked": len(report["reports"]), "analyzed": report["declarations_analyzed"],
                      "with_findings": sum(bool(row["findings"]) for row in report["reports"]),
                      "complete": sum(row["coverage_complete"] for row in report["reports"])}))


if __name__ == "__main__":
    main()
