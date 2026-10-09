"""Fetches the third-party test suites the tests read into .corpora/, each at a pinned commit.

    python3 tests/corpora/fetch.py            # every suite
    python3 tests/corpora/fetch.py toml-test  # the ones named

A suite is a git repository, fetched at its commit alone and without the blobs of the files it
does not need (a partial clone, a sparse checkout): the commit is its checksum, and nothing else of
it is downloaded. A suite already at its commit is left alone, so this runs in no time once done.
Its bytes are kept as they are upstream, CRs and invalid UTF-8 included - they are what is being
tested - so no checkout converts line endings, whatever git's configuration says.
"""

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, ".corpora")

# name -> (repository, commit, sparse-checkout patterns)
SUITES = {
    # fjson's conformance (D24)
    "JSONTestSuite": (
        "https://github.com/nst/JSONTestSuite",
        "1ef36fa01286573e846ac449e8683f8833c5b26a",
        ["/LICENSE", "/test_parsing/", "/test_transform/"],
    ),
    # ftoml's conformance (D25): v2.2.0
    "toml-test": (
        "https://github.com/toml-lang/toml-test",
        "ce08da1ddb075d1c7596d663c7fcba9a2ae02c5c",
        ["/LICENSE", "/tests/"],
    ),
    # std's sources, which go to definition reads with the SDK's .cjo (D65): the commit of
    # cangjie_runtime the nightly in .cangjie-version was built from, as its release notes name it
    "cangjie_runtime": (
        "https://github.com/cangjie-bot/cangjie_runtime",
        "5d555bcc34d656a064b904ecc61e0575b98dddab",
        ["/LICENSE", "/stdlib/libs/std/"],
    ),
}


# what git exports to a hook names cjls's own repository, and every command below would act on it:
# run by the pre-push hook in a worktree, this fetched a suite into cjls and sparse-checked it out
REPOSITORY = [
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_PREFIX",
]
ENV = {key: value for key, value in os.environ.items() if key not in REPOSITORY}


def git(cwd, *args):
    subprocess.run(["git", "-c", "core.autocrlf=false", *args], cwd=cwd, env=ENV, check=True)


def head(dest):
    result = subprocess.run(["git", "rev-parse", "HEAD"], cwd=dest, env=ENV, capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def fetch(name):
    url, commit, patterns = SUITES[name]
    dest = os.path.join(CORPORA, name)
    if os.path.isdir(os.path.join(dest, ".git")) and head(dest) == commit:
        print(f"{name}: at {commit[:12]}", file=sys.stderr)
        return
    print(f"{name}: fetching {url} at {commit[:12]}", file=sys.stderr)
    os.makedirs(dest, exist_ok=True)
    if not os.path.isdir(os.path.join(dest, ".git")):
        git(dest, "init", "-q")
        git(dest, "remote", "add", "origin", url)
    # the repository's own settings, over any global ones: bytes as they are, whatever the platform
    git(dest, "config", "core.autocrlf", "false")
    with open(os.path.join(dest, ".git", "info", "attributes"), "w") as attributes:
        attributes.write("* -text\n")
    git(dest, "sparse-checkout", "set", "--no-cone", *patterns)
    git(dest, "fetch", "-q", "--depth", "1", "--filter=blob:none", "origin", commit)
    git(dest, "checkout", "-q", "--detach", commit)


def main(names):
    unknown = [name for name in names if name not in SUITES]
    if unknown:
        sys.exit(f"no such suite: {', '.join(unknown)} (there are {', '.join(SUITES)})")
    for name in names or SUITES:
        fetch(name)


if __name__ == "__main__":
    main(sys.argv[1:])
