#!/usr/bin/env python3
"""The workspace's line coverage, from cjcov's `coverage.json` (D49).

    cjcov -r . -s modules -x -j -o <dir>
    python3 .github/scripts/coverage.py <dir>/coverage.json [--badge badge.json]

Prints `hit/total percent`, over the `modules/*/src/**` files that are neither `*_test.cj` nor
in `GENERATED`, `MACROS` or `TEST_SUPPORT`. `--badge` writes a shields.io endpoint JSON.
"""

import argparse
import json
import math
import sys
from pathlib import Path, PurePosixPath


# What a generator writes, by path: a directory (ends in `/`) or a file. A list, not a header
# check, so that a new generated file is a decision in a diff (D49).
GENERATED = (
    "modules/cjls/src/lsp_types/",  # lsp_codegen
    "modules/cjo/src/format.cj",  # fbs_codegen
    "modules/cjsyntax/src/ast/nodes.cj",  # syntax_codegen
    "modules/cjsyntax/src/syntax_kind.cj",  # syntax_codegen
    "modules/fnum/src/pow10_table.cj",  # pow10_table.py
    "modules/fnum/src/ryu_table.cj",  # from ryu's d2s_full_table.h
)

# Macro packages expand at compile time, and the instrumentation does not see what runs then.
MACROS = (
    "modules/calca/src/macros/",
    "modules/cjls/src/macros/",
    "modules/stdxx/src/deriving/",
)

# Packages only tests import: what runs them is a test, as much as a `*_test.cj` is.
TEST_SUPPORT = ("modules/loupe/src/fixture/",)


def counts(report: dict) -> tuple[int, int]:
    hit = total = 0
    for file in report["fileLists"]:
        # cjcov writes the platform's separator
        path = PurePosixPath(file["filepath"].replace("\\", "/"))
        parts = path.parts
        if len(parts) < 4 or parts[0] != "modules" or parts[2] != "src":
            continue
        if path.name.endswith("_test.cj") or str(path).startswith(GENERATED + MACROS + TEST_SUPPORT):
            continue
        hit += len(file["hitLines"])
        total += file["totalLines"]
    return hit, total


def color(percent: int) -> str:
    for floor, name in ((90, "brightgreen"), (80, "green"), (70, "yellowgreen"), (60, "yellow"), (50, "orange")):
        if percent >= floor:
            return name
    return "red"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("report", type=Path, help="cjcov's coverage.json")
    parser.add_argument("--badge", type=Path, help="write a shields.io endpoint JSON here")
    args = parser.parse_args()

    hit, total = counts(json.loads(args.report.read_text()))
    if total == 0:
        print("no source file of modules/*/src in the report", file=sys.stderr)
        return 1
    percent = 100 * hit / total
    print(f"{hit}/{total} {percent:.1f}%")
    if args.badge:
        # rounded down, the text and the color alike: 99.6 is not 100%
        shown = math.floor(percent)
        badge = {
            "schemaVersion": 1,
            "label": "coverage",
            "message": f"{shown}%",
            "color": color(shown),
        }
        args.badge.write_text(json.dumps(badge) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
