# Changelog
All notable changes to this project will be documented in this file. See [conventional commits](https://www.conventionalcommits.org/) for commit guidelines.

- - -
## [v0.2.0](https://github.com/ide4cj/cjls/compare/d28a9c0f41fdf4129337ca4e60d39947fbb8a9c1..v0.2.0) - 2026-09-28
#### Features
- (**fjson**) a JSON reader and writer over bytes (#32) - ([d28a9c0](https://github.com/ide4cj/cjls/commit/d28a9c0f41fdf4129337ca4e60d39947fbb8a9c1)) - FilaCo
- ![BREAKING](https://img.shields.io/badge/BREAKING-red) (**stdxx**) serde's derives ToJson and FromJson under one @Serde marker, and the wire on fjson (#40) - ([58580da](https://github.com/ide4cj/cjls/commit/58580da68bf123f7ef4a50b18810bf79a34197b8)) - FilaCo
#### Bug Fixes
- (**fjson**) read a lone surrogate as U+FFFD, and hold fjson to JSONTestSuite and a fuzzer (D24) (#44) - ([36e6861](https://github.com/ide4cj/cjls/commit/36e6861d35445cc5c7bc2840dbcb175e9c877782)) - FilaCo
#### Performance Improvements
- typing 3.8x faster, generics specialized and positions in one descent (#22) (#62) - ([b617d26](https://github.com/ide4cj/cjls/commit/b617d26b020404b50f6392e9f3081da966875840)) - FilaCo
#### Documentation
- (**prior-art**) give R9 its row among the references (#67) - ([2184e88](https://github.com/ide4cj/cjls/commit/2184e88debad1914773c9887a2dbf85af30615e8)) - FilaCo
- open questions move to GitHub issues (#57) - ([6e1227a](https://github.com/ide4cj/cjls/commit/6e1227af7034a0ec9da093e1fe3798cad4e20737)) - FilaCo
#### Tests
- (**perf**) measure speed and memory of language servers over stdio (#23) - ([0cd40c3](https://github.com/ide4cj/cjls/commit/0cd40c35f0748a7149877e72b2188a450c44909f)) - FilaCo
#### Continuous Integration
- run the tests without the progress report, which fails them now and then (#60) - ([c7658b8](https://github.com/ide4cj/cjls/commit/c7658b8c6c389fd48f094694a988c709b0be6c8c)) - FilaCo

- - -


## v0.1.0

The first release of cjls, a language server for [Cangjie](https://cangjie-lang.cn) written in Cangjie. It reads each file on its own, from its syntax: no names are resolved and no types inferred yet, so everything below holds for code that does not compile as well.

#### What it does

- **Document symbols** (`textDocument/documentSymbol`): the outline of a file — classes, structs, interfaces, enums and their constructors, extensions, functions and methods, `main`, macros, constructors, properties, fields, variables, type aliases — nested as declared.
- **Syntax errors** as diagnostics: pulled (`textDocument/diagnostic`) by a client that can, pushed (`textDocument/publishDiagnostics`) after every change to one that cannot. The parser follows the compiler's own: checked against its test suite (~98k files), it reports no error in a file the compiler parses.
- **Semantic highlighting** (`textDocument/semanticTokens/full` and `/range`): keywords, including contextual ones where they are keywords; comments, documentation apart; literals and the code inside interpolated strings; operators; builtin annotations and macro calls; names where they are declared, by kind, with `declaration`, `readonly`, `static` and `deprecated`; type names and builtin types.
- **Document sync**: incremental changes, positions in UTF-8 when the client offers it and UTF-16 otherwise.
- **Responsive while typing**: every request is answered from a snapshot of the files as it arrived; one the files changed under is cancelled (`ContentModified`), and results are computed incrementally, only what an edit touched computed again.

#### Where it runs

- One static binary for macOS arm64, Linux x64 and Windows x64, each tested end to end with the capabilities VS Code and Neovim send. It needs no Cangjie SDK.
- **Neovim** 0.11 or newer: [cangjie.nvim](https://github.com/ide4cj/cangjie.nvim) downloads this release and starts it on `.cj` files. Any other editor that speaks LSP over stdio can run `cjls` itself, with the nearest `cjpm.toml` as the root.

- - -
