"""Warnings as errors for cjc, which has no such flag: `python deny_warnings.py cjpm build`.

Runs the command and passes its output through, then fails as it did, or if the output holds a
warning other than those std's own macros leave in code we cannot change. The packages we do not
own (the generated `cjls.lsp_types`, the vendored `cjtoml`) are exempted in their `cjpm.toml`, so
their warnings never reach here.
"""

import re
import subprocess
import sys

ANSI = re.compile(r"\x1b\[[0-9;]*m")
MACRO = re.compile(r"the warning originates in the macro `(\w+)`")

# (macro the warning comes from, what its note says) — std's macros, whatever we write:
# `@Derive[Equatable, Hashable]` on an enum with payloads emits a `check_<Variant>_<n>` per payload
# that nothing calls, and `@Test` wraps `@AssertThrows` and `@Expect` in branches that cannot run
TOLERATED = [
    ("Derive", re.compile(r"unused function:'check_\w+'")),
    ("DeriveExt", re.compile(r"unused function:'check_\w+'")),  # the `@Derive` inside it
    ("Test", re.compile(r"unreachable (block in 'if' )?expression")),
]


def warnings(lines):
    """Each warning as its lines: from `warning:` to the blank line, or the next warning."""
    current = None
    for line in lines:
        if line.startswith("warning:"):
            if current:
                yield current
            current = [line]
        elif current is not None:
            if line.strip() == "" or re.match(r"\d+ warnings? generated", line):
                yield current
                current = None
            else:
                current.append(line)
    if current:
        yield current


def tolerated(warning):
    macro = MACRO.search(warning[0])
    if not macro:
        return False
    notes = [line for line in warning if line.startswith("note:")]
    return any(
        macro.group(1) == name and notes and all(pattern.search(n) for n in notes)
        for name, pattern in TOLERATED
    )


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: deny_warnings.py <command> [args...]")
    process = subprocess.Popen(
        sys.argv[1:], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding="utf-8", errors="replace"
    )
    lines = []
    for line in process.stdout:
        sys.stdout.write(line)
        sys.stdout.flush()
        lines.append(ANSI.sub("", line.rstrip("\r\n")))
    if process.wait() != 0:
        sys.exit(process.returncode)

    denied = []
    seen = set()
    for warning in warnings(lines):
        # the same warning is printed each time its package is compiled
        key = "\n".join(warning)
        if key in seen or tolerated(warning):
            continue
        seen.add(key)
        denied.append(warning)

    if denied:
        print(f"\nerror: {len(denied)} warning(s), and warnings are errors here:", file=sys.stderr)
        for warning in denied:
            location = next((line.strip() for line in warning if "==>" in line), "")
            print(f"  {warning[0]} {location}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
