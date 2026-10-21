#!/usr/bin/env bash
# Runner-installed libraries can hide dependencies a user's machine does not have.
# Test the release executable in the baseline userspace, without an SDK or build tools.
set -euo pipefail
binary=$(realpath "$1")
docker run --rm \
  --mount "type=bind,src=$binary,dst=/usr/local/bin/cjls,readonly" \
  ubuntu:22.04 bash -ec '
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends libstdc++6
    dpkg-query -W libc6 libstdc++6
    ldd /usr/local/bin/cjls
    /usr/local/bin/cjls --config-schema > /dev/null
  '
