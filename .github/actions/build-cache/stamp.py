"""Gives every file git tracks an mtime taken from its content.

    python3 stamp.py

cjpm's incremental cache knows a source by its mtime alone, and a checkout gives every file the
time of the checkout, so a restored `target` would be compiled again from the first package to
the last. An mtime made of a hash of the file is the same in every checkout where the content is,
and differs where it is not (D27).
"""

import hashlib
import os
import subprocess

# 2^28 seconds after this: 2001 to 2009, all in the past, none before the epoch on any platform
BASE = 1_000_000_000


def main():
    listing = subprocess.run(["git", "ls-files", "-z"], check=True, capture_output=True).stdout
    for path in map(os.fsdecode, filter(None, listing.split(b"\0"))):
        # a submodule is a directory, a symlink stamps its target; a deleted file has none
        if os.path.islink(path) or not os.path.isfile(path):
            continue
        with open(path, "rb") as f:
            digest = hashlib.sha256(f.read()).digest()
        mtime = BASE + (int.from_bytes(digest[:4], "big") >> 4)
        os.utime(path, (mtime, mtime))


if __name__ == "__main__":
    main()
