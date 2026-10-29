#!/usr/bin/env bash
# Package the already-built executable; the workflow tests this archive's copy before upload.
set -euo pipefail
binary=$(realpath "$1")
mkdir -p "$2"
dist=$(cd "$2" && pwd)
sha=$(git rev-parse HEAD)
name="cjmcp-linux-x86_64-${sha:0:12}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/$name"
cp "$binary" "$work/$name/cjmcp"
chmod +x "$work/$name/cjmcp"
cp modules/cjmcp/README.md LICENSE-MIT LICENSE-APACHE .cangjie-version .cangjie-sha256 "$work/$name/"
{
  echo "commit=$sha"
  echo "target=x86_64-unknown-linux-gnu"
  echo "sdk=$(tr -d '[:space:]' < .cangjie-version)"
} > "$work/$name/BUILD-INFO"
tar -czf "$dist/$name.tar.gz" -C "$work" "$name"
(cd "$dist" && sha256sum "$name.tar.gz" > SHA256SUMS)
