#!/usr/bin/env python3
"""Compare formatter CLI wall time, including process startup and file I/O.

Build cjls first and run this script inside a coordinated measurement window.
Results describe each tool's own output, not equivalent formatting algorithms.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile
import time


def run_formatter(command: list[str], source: Path, original: bytes) -> float:
    """Restore identical input outside the timer and reject failed/empty output."""
    source.write_bytes(original)
    started = time.perf_counter_ns()
    result = subprocess.run(command, capture_output=True, timeout=120)
    elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000
    if result.returncode or b"error:" in result.stderr.lower():
        raise RuntimeError(
            f"{command[0]} failed: {result.stdout.decode(errors='replace')}"
            f"{result.stderr.decode(errors='replace')}"
        )
    if not source.read_bytes().strip():
        raise RuntimeError(f"{command[0]} produced empty output")
    return elapsed_ms


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cjls", type=Path, required=True)
    parser.add_argument("--cjfmt", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repetitions", type=int, default=9)
    parser.add_argument("--warmup", type=int, default=1)
    inputs = parser.add_mutually_exclusive_group()
    inputs.add_argument("--sizes", type=int, nargs="+", default=[1, 100, 1000, 10000])
    inputs.add_argument("--inputs", type=Path, nargs="+", help="read-only source files to copy and format")
    args = parser.parse_args()
    if args.repetitions < 2 or args.warmup < 0 or any(n < 1 for n in args.sizes):
        parser.error("use at least two repetitions, nonnegative warmup and positive sizes")
    cjls = args.cjls.resolve(strict=True)
    cjfmt = args.cjfmt.resolve(strict=True)
    if args.inputs:
        cases = [(str(path.resolve()), None, path.read_bytes()) for path in args.inputs]
    else:
        cases = [
            (
                f"calls-{count}", count,
                ("func f() {\n"
                 + "call(firstArgument, secondArgument, thirdArgument)\n" * count
                 + "}\n").encode(),
            )
            for count in args.sizes
        ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    report = {
        "platform": platform.platform(),
        "commands": {"cjls": str(cjls), "cjfmt": str(cjfmt)},
        "binary_sha256": {
            name: hashlib.sha256(path.read_bytes()).hexdigest()
            for name, path in [("cjls", cjls), ("cjfmt", cjfmt)]
        },
        "runtime_env": {
            name: os.environ.get(name)
            for name in ["cjProcessorNum", "cjHeapSize", "CANGJIE_HOME"]
        },
        "affinity": sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None,
        "warmup": args.warmup,
        "repetitions": args.repetitions,
        "line_width": 100,
        "cases": [],
    }
    with tempfile.TemporaryDirectory(dir=args.output.parent) as directory:
        root = Path(directory).resolve()
        source = root / "input.cj"
        config = root / "cangjie-format.toml"
        config.write_text('indentWidth = 4\nlinelimitLength = 100\nlineBreakType = "LF"\n')
        commands = {
            "cjls": [str(cjls), "fmt", str(source)],
            "cjfmt": [str(cjfmt), "-f", str(source), "-c", str(config)],
        }
        for name_of_input, count, original in cases:
            samples = {name: [] for name in commands}
            outputs = {}
            for repetition in range(args.warmup + args.repetitions):
                # Alternate order to reduce systematic first/second-tool bias.
                order = list(commands) if repetition % 2 == 0 else list(reversed(commands))
                for name in order:
                    elapsed = run_formatter(commands[name], source, original)
                    formatted = source.read_bytes()
                    if name in outputs and outputs[name] != formatted:
                        raise RuntimeError(f"{name} produced inconsistent output")
                    outputs[name] = formatted
                    if repetition >= args.warmup:
                        samples[name].append(elapsed)
            # Validate idempotence outside the measured samples. cjfmt may exit zero on errors.
            for name, formatted in outputs.items():
                run_formatter(commands[name], source, formatted)
                if source.read_bytes() != formatted:
                    raise RuntimeError(f"{name} output is not idempotent")
            case = {
                "input": name_of_input,
                "statements": count,
                "input_bytes": len(original),
                "input_sha256": hashlib.sha256(original).hexdigest(),
                "results": {
                    name: {
                        "samples_ms": values,
                        "median_ms": statistics.median(values),
                        "min_ms": min(values),
                        "max_ms": max(values),
                        "output_bytes": len(outputs[name]),
                        "output_sha256": hashlib.sha256(outputs[name]).hexdigest(),
                    }
                    for name, values in samples.items()
                },
            }
            report["cases"].append(case)
            print(json.dumps(case), flush=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
