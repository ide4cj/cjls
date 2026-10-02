#!/usr/bin/env bash
# The archives a release publishes, stable or nightly, from the binaries CI built and tested (its
# `cjls-<OS>` artifacts, under $1), into $2 with their SHA256SUMS: what the editor clients download
# (D16, D32), so their names never change.
set -euo pipefail
artifacts=$(cd "$1" && pwd)
mkdir -p "$2"
dist=$(cd "$2" && pwd)
work=$(mktemp -d)
package() { # artifact, target, archive format
  dir="cjls-$2"
  mkdir "$work/$dir"
  cp "$artifacts/cjls-$1"/* README.md LICENSE-MIT LICENSE-APACHE "$work/$dir/"
  chmod +x "$work/$dir"/cjls*
  if [ "$3" = zip ]; then
    (cd "$work" && zip -qr "$dist/$dir.zip" "$dir")
  else
    tar -czf "$dist/$dir.tar.gz" -C "$work" "$dir"
  fi
}
package macOS aarch64-apple-darwin tar
package Linux x86_64-unknown-linux-gnu tar
package Windows x86_64-pc-windows-gnu zip
(cd "$dist" && sha256sum -- * > SHA256SUMS)
ls -l "$dist"
