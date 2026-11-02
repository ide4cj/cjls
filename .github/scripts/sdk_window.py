"""Select the release window and run pin-built tests against one installed SDK."""

import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PACKAGES = ("cjo", "loupe.vfs", "loupe.hir", "loupe")


def matrix(window=ROOT / ".cangjie-window"):
    releases = json.loads(window.read_text())
    return {"include": [{"channel": channel, "version": releases[channel]["version"]}
                        for channel in ("lts", "sts")]}


def test(sdk, binaries=ROOT / "target/test/release/unittest_bin"):
    sdk = Path(sdk).resolve(strict=True)
    environment = dict(os.environ, CANGJIE_HOME=str(sdk), cjHeapSize="2GB")
    failed = False
    for package in PACKAGES:
        print(f"SDK {sdk}: {package}", flush=True)
        # Missing binaries are failures too; never let a partial build reduce the gate.
        result = subprocess.run([str(binaries / package), "--no-progress", "--timeout-each=2m"],
                                env=environment, check=False)
        failed |= result.returncode != 0
    return int(failed)


if __name__ == "__main__":
    if sys.argv[1:] == ["matrix"]:
        print(json.dumps(matrix(), separators=(",", ":")))
    elif len(sys.argv) == 3 and sys.argv[1] == "test":
        sys.exit(test(sys.argv[2]))
    else:
        sys.exit("usage: sdk_window.py matrix | test <sdk>")
