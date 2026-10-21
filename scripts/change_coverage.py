#!/usr/bin/env python3
"""Generate current coverage or inspect changed files using CI's selection policy.

Run from a worktree root with the pinned SDK loaded and corpora fetched.
No baseline coverage comparison is performed; --base only selects changed files.
"""

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REPORT = Path("coverage/coverage.json")
STAMP = Path("coverage/inputs.json")
spec = importlib.util.spec_from_file_location("ci_coverage", ROOT / ".github/scripts/coverage.py")
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


def git(*args):
    return subprocess.check_output(["git", *args]).decode().rstrip("\n")


def inputs():
    """Fingerprint source/config inputs, including local new files; ignore build output."""
    names = git("ls-files", "-z", "--cached", "--others", "--exclude-standard").split("\0")
    digest = hashlib.sha256()
    for name in sorted(set(names)):
        if not name or not (name.endswith((".cj", ".toml")) or name.startswith(".cangjie-")
                            or name == "tests/corpora/fetch.py"):
            continue
        path = Path(name)
        digest.update(name.encode() + b"\0")
        digest.update(path.read_bytes() if path.is_file() else b"<missing>")
        digest.update(b"\0")
    return digest.hexdigest()


def read_report():
    report = json.loads(REPORT.read_text())
    if not isinstance(report, dict) or not isinstance(report.get("fileLists"), list):
        raise ValueError("malformed coverage report: expected fileLists")
    paths = set()
    for file in report["fileLists"]:
        if (not isinstance(file, dict) or not isinstance(file.get("filepath"), str)
                or not isinstance(file.get("hitLines"), list)
                or type(file.get("totalLines")) is not int
                or not 0 <= len(file["hitLines"]) <= file["totalLines"]):
            raise ValueError("malformed coverage report: invalid file entry")
        # Reporting normalizes separators; duplicate entries would silently overwrite counts.
        path = file["filepath"].replace("\\", "/")
        if path in paths:
            raise ValueError(f"malformed coverage report: duplicate coverage path {path}")
        paths.add(path)
    if not Path("coverage/index.html").is_file():
        raise ValueError("missing coverage/index.html; rerun coverage generation")
    return report


def generate():
    before = inputs()
    STAMP.unlink(missing_ok=True)
    # A failed generation must not silently reuse a previous report.
    REPORT.unlink(missing_ok=True)
    Path("coverage/index.html").unlink(missing_ok=True)
    subprocess.run([
        "cjpm", "test", "--coverage", "-g", "--no-progress", "--timeout-each=2m",
        "--exclude-tags", "gate", "--target-dir", "target/cov",
    ], check=True)
    subprocess.run([
        "cjcov", "-r", ".", "-s", "modules", "-x", "-j", "--html-details", "-o", "coverage",
    ], check=True)
    if before != inputs():
        raise ValueError("inputs changed during coverage generation; rerun on a stable worktree")
    read_report()
    # Bind provenance to this report too, not just to the current sources.
    STAMP.write_text(json.dumps({
        "inputs": before, "report": hashlib.sha256(REPORT.read_bytes()).hexdigest(),
        "revision": git("rev-parse", "HEAD"),
    }) + "\n")
    print("coverage generated for stable worktree inputs")


def changed(base):
    ancestor = git("merge-base", base, "HEAD")
    tracked = git("diff", "--name-only", "--no-renames", "--diff-filter=AM", "-z", ancestor, "--", "modules").split("\0")
    new = git("ls-files", "--others", "--exclude-standard", "-z", "--", "modules").split("\0")
    return sorted({name for name in tracked + new if name.endswith(".cj")})


def inspect(base):
    if not REPORT.is_file() or not STAMP.is_file():
        raise ValueError("missing coverage report or provenance; run: python3 scripts/change_coverage.py run")
    stamp = json.loads(STAMP.read_text())
    if not isinstance(stamp, dict):
        raise ValueError("malformed coverage provenance; rerun coverage generation")
    if stamp.get("inputs") != inputs() or stamp.get("report") != hashlib.sha256(REPORT.read_bytes()).hexdigest():
        raise ValueError("stale coverage report or changed inputs; rerun: python3 scripts/change_coverage.py run")
    report = read_report()
    files = {f["filepath"].replace("\\", "/"): f for f in report["fileLists"]}
    missing = False
    selected = changed(base)
    if not selected:
        print("no added/modified Cangjie files relative to merge-base with " + base)
    for name in selected:
        if not policy.included(name):
            print(f"{name}: excluded by CI coverage policy")
        elif name not in files:
            print(f"{name}: missing from coverage report")
            missing = True
        else:
            file = files[name]
            print(f"{name}: {len(file['hitLines'])}/{file['totalLines']}")
    return int(missing)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("run", help="generate a fresh report and input provenance")
    report = commands.add_parser("report", help="report coverage for added/modified files")
    report.add_argument("--base", default="origin/master", help="merge-base reference; must already exist locally")
    args = parser.parse_args()
    if Path.cwd().resolve() != ROOT:
        parser.error("run from the repository/worktree root")
    try:
        if args.command == "run":
            generate()
            return 0
        return inspect(args.base)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"coverage: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
