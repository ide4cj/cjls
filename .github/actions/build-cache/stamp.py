"""Gives every file git tracks an mtime taken from the content of its directory.

    python3 stamp.py

cjpm's incremental cache knows a source by its mtime alone, and a checkout gives every file the
time of the checkout, so a restored `target` would be compiled again from the first package to
the last. An mtime made of a hash of the content is the same in every checkout where the content
is, and differs where it is not (D27).

The hash is the directory's, not the file's: cjpm reads a package's imports again only when the
newest mtime among its files changed (D28). A file changed or added with an mtime of its own that
is not the newest would leave the package compiled against its old imports, before a package it
now imports. One mtime for all the files of a directory is a new newest one whenever any of them
changed, was added or removed.
"""

import hashlib
import os
import subprocess
from collections import defaultdict

# 2^28 seconds after this: 2001 to 2009, all in the past, none before the epoch on any platform
BASE = 1_000_000_000


def main():
    listing = subprocess.run(["git", "ls-files", "-z"], check=True, capture_output=True).stdout
    directories = defaultdict(list)
    for path in map(os.fsdecode, filter(None, listing.split(b"\0"))):
        # a submodule is a directory, a symlink stamps its target; a deleted file has none
        if os.path.islink(path) or not os.path.isfile(path):
            continue
        directories[os.path.dirname(path)].append(path)
    for paths in directories.values():
        digest = hashlib.sha256()
        for path in sorted(paths):
            with open(path, "rb") as f:
                content = hashlib.sha256(f.read()).digest()
            digest.update(os.path.basename(path).encode() + b"\0" + content)
        mtime = BASE + (int.from_bytes(digest.digest()[:4], "big") >> 4)
        for path in paths:
            os.utime(path, (mtime, mtime))


if __name__ == "__main__":
    main()
