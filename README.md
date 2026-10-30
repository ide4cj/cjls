# cjls

[![coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/ide4cj/cjls/badges/coverage.json)](https://github.com/ide4cj/cjls/actions/workflows/coverage.yml)

A language server for [Cangjie](https://cangjie-lang.cn), written in Cangjie:
incremental, answering from a snapshot while you type,
reporting no error in code the compiler accepts.

It is early: each file is read on its own, from its syntax. What it does today is in the
[changelog](CHANGELOG.md) — document symbols, syntax errors, semantic highlighting; names, types,
completion and go-to-definition are to come.

## Install

**Neovim** 0.11 or newer: [cangjie.nvim](https://github.com/ide4cj/cangjie.nvim) downloads the server
and starts it on `.cj` files.

**Any other editor**: download the archive for your platform from the
[latest release](https://github.com/ide4cj/cjls/releases/latest) — macOS arm64, Linux x64, Windows
x64 — check it against `SHA256SUMS`, and put `cjls` on your `PATH`. The Cangjie runtime is linked
statically; no Cangjie SDK is needed. Linux releases target Ubuntu 22.04 or newer, with system
glibc and an up-to-date `libstdc++6` package (`GLIBCXX_3.4.30`). Run it over stdio, with the nearest
`cjpm.toml`'s directory as the root. `CJLS_LOG_LEVEL`
(`OFF`, `ERROR`, `WARN`, `INFO` by default, `DEBUG`, `TRACE`) sets what it logs to stderr.

**Nix (Linux x64)**: add `github:ide4cj/cjls` as a flake input named `cjls`, then
add `inputs.cjls.packages.${pkgs.stdenv.hostPlatform.system}.default` to
`environment.systemPackages` (NixOS) or `home.packages` (Home Manager).

VS Code and Zed extensions are planned.

## Build

Use the pinned Cangjie SDK and matching stdx. [Development](docs/development.md)
covers setup, building, testing and preparing a review.

The architecture and design rules are in [`docs/`](docs/README.md); adding a
request in [CONTRIBUTING.md](CONTRIBUTING.md); agent working instructions in
[AGENTS.md](AGENTS.md).

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE) or [MIT license](LICENSE-MIT)
at your option. Unless you explicitly state otherwise, any contribution intentionally submitted for
inclusion in cjls by you, as defined in the Apache-2.0 license, shall be dual licensed as above,
without any additional terms or conditions.
