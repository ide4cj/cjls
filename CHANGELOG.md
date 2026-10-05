# Changelog
All notable changes to this project will be documented in this file. See [conventional commits](https://www.conventionalcommits.org/) for commit guidelines.

- - -
## [v0.3.0](https://github.com/ide4cj/cjls/compare/3225c41716083f99cd21bdc169583507e8e86b2b..v0.3.0) - 2026-10-05
#### Features
- (**calca**) an LRU evicts as it touches, within a revision too (#85) (#132) - ([32f6443](https://github.com/ide4cj/cjls/commit/32f64434cddb83b25909338e312bf18a33c9fae5)) - FilaCo
- (**calca**) a cycle across handles recovers by its fallbacks, as on one handle (#99) (#126) - ([6bd491b](https://github.com/ide4cj/cjls/commit/6bd491b0cee6ed0df88111ae7bf66e984d7f5975)) - FilaCo
- (**calca**) tracked methods, @CalcaTracked on an extend and on its methods (#14) (#78) - ([f4d0a3e](https://github.com/ide4cj/cjls/commit/f4d0a3e91dca20f1ec3bcee97a4106586d3d96fe)) - FilaCo
- (**calca**) batched writes, every set and create in storage.batch one revision (#14) (#77) - ([19dc579](https://github.com/ide4cj/cjls/commit/19dc5791f30725661d2e703ceb79e72e4e4156be)) - FilaCo
- (**calca**) recover from a cycle with @CalcaTracked[cycleResult: fallback] (#14) (#75) - ([3b25b91](https://github.com/ide4cj/cjls/commit/3b25b919082cb426a9895e30895d807c4a4bb11d)) - FilaCo
- (**calca**) one computation per memo; a wait that would close a loop across threads is a cycle (D29, #14) (#74) - ([11a6cc9](https://github.com/ide4cj/cjls/commit/11a6cc91d319c86f32332910d70ffafc61cd3359)) - FilaCo
- (**calca**) tracked functions of several arguments, keyed by one generated struct (#14) (#72) - ([c180f6e](https://github.com/ide4cj/cjls/commit/c180f6e994c4195878577e22d28a391a885308c4)) - FilaCo
- (**calca**) singleton inputs, @CalcaInput[singleton] with get and tryGet (#14) (#71) - ([55691d8](https://github.com/ide4cj/cjls/commit/55691d8d25e3224be8c519ab426ed69f2ba82660)) - FilaCo
- (**cjls**) start over with a heap of 2 GB unless cjHeapSize is set; a load keeps a sixteenth of the heap (D31) (#81) - ([0610d84](https://github.com/ide4cj/cjls/commit/0610d84fc85f915f45f108b9fecd8eaa6bcdb696)) - FilaCo
- (**cjls**) load the workspace, follow its files and folders, answer workspace/symbol (#12) (#79) - ([5534b50](https://github.com/ide4cj/cjls/commit/5534b500fc7918d28c619ca2652ef8928567f8b3)) - FilaCo
- (**cjls**) cjls/memoryUsage, the runtime's heap and collections on request (#22) (#64) - ([d176002](https://github.com/ide4cj/cjls/commit/d17600248788ecca0295997b050890fdc2babb33)) - FilaCo
- (**cjo**) a reader of .cjo files, its views generated from CjoFormat.fbs by fbs_codegen (#68) (#134) - ([9cc6e03](https://github.com/ide4cj/cjls/commit/9cc6e03b14115aaca3ca57f393277f13fe5b1402)) - FilaCo
- (**cjsyntax**) Has* interfaces of the views, and a name without its backquotes (#103) (#128) - ([a48d6f9](https://github.com/ide4cj/cjls/commit/a48d6f9dee8b00165a2c2446e82cb8288c6c4d79)) - FilaCo
- ![BREAKING](https://img.shields.io/badge/BREAKING-red) (**ftoml**) TOML 1.1 of our own, ToToml and FromToml derived through @Serde; cjtoml and DataModel go (D25) (#58) - ([3225c41](https://github.com/ide4cj/cjls/commit/3225c41716083f99cd21bdc169583507e8e86b2b)) - FilaCo
- (**index_map**) == on IndexMap and IndexSet, and ConcurrentIndexMap.getOrAdd (#117) (#146) - ([92e14b0](https://github.com/ide4cj/cjls/commit/92e14b020f7162f5f46d3cacdc82580ce5f49e7a)) - FilaCo
- (**loupe**) a package's def map, its declarations by name (D45) (#48) (#150) - ([7415f63](https://github.com/ide4cj/cjls/commit/7415f63d19bc3f8cf20cc25d920790aed0b49c27)) - FilaCo
- (**loupe**) std and the binary dependencies as inputs from their .cjo, lowered into the item tree (#68) (#142) - ([ba4100e](https://github.com/ide4cj/cjls/commit/ba4100ef2a39e6c922605e8af40ff12631c7c32c)) - FilaCo
- (**loupe**) the .cjo of std and of bin-dependencies are inputs of their bytes, lowered into item trees (#68) (#136) - ([11b45d8](https://github.com/ide4cj/cjls/commit/11b45d88a296a52c9d34c0ad718a3e7f0d1f8c2d)) - FilaCo
- (**loupe**) items named by ids edits elsewhere leave alone, and a file's item tree (#97) (#122) - ([463d1c5](https://github.com/ide4cj/cjls/commit/463d1c52b84eb897ba7a0a52930f34c0f5c51a8f)) - FilaCo
- (**project_model**) a project model in loupe, found from cj-project.json, cjpm.toml or loose files (#69) (#121) - ([c76ab7e](https://github.com/ide4cj/cjls/commit/c76ab7e8d6ccfff724d007f5cbe33d9b296b2751)) - FilaCo
#### Bug Fixes
- (**calca**) a query swallowing calca's unwinding stores no memo; `Cancelled` is `CancelledException` (#100) (#144) - ([0ebfee7](https://github.com/ide4cj/cjls/commit/0ebfee7bfa1c146e57e928eaf08ac866a40be750)) - FilaCo
- (**calca**) a memo keyed by several values goes with any interned one among them (#98) (#125) - ([f337cc9](https://github.com/ide4cj/cjls/commit/f337cc97f3892a64d0fe6364f620860f2c7aca4d)) - FilaCo
- (**calca**) overloaded tracked functions, their generated names mangled with the parameter types (#14) (#92) - ([988e0f7](https://github.com/ide4cj/cjls/commit/988e0f71068c7507caccc60533bc1c20e6bf40f9)) - FilaCo
- (**ci**) stamp a package's files with one mtime, so cjpm reads its imports again (D28) (#73) - ([7e6a42d](https://github.com/ide4cj/cjls/commit/7e6a42d9f44fde0ceff8ea4fb1778d817c4b2c01)) - FilaCo
- (**cjls**) an extend goes out as a Namespace symbol, not an Object (#133) - ([cbdda2c](https://github.com/ide4cj/cjls/commit/cbdda2c3a6a40eb52d40d74b9e4ce16569aef96c)) - FilaCo
- (**cjsyntax**) a line starting a top-level-only declaration ends an unclosed block (#102) (#138) - ([28144eb](https://github.com/ide4cj/cjls/commit/28144ebc0811e12bdcf6b0f72a27f652b583dbf3)) - FilaCo
- (**ginkgo**) a grammar bug gives an error tree, not an exception, and rewinding counts towards the step limit (#101) (#131) - ([2084fb0](https://github.com/ide4cj/cjls/commit/2084fb023bfc631ab3bab9ea8751b569b8edf3c1)) - FilaCo
- (**jsonrpc**) every spawn and the read loop catch an Error too, answered InternalError and logged (S13, #83) (#130) - ([a7ff3f1](https://github.com/ide4cj/cjls/commit/a7ff3f154cadc378d3d602890d84b3a2ae7bbf8a)) - FilaCo
- (**syntax_codegen**) an accessor finds a child by the tokens between it and its rivals (D41) (#139) (#143) - ([895158c](https://github.com/ide4cj/cjls/commit/895158cce72de17f9e48efcd99b4eef26634e3e3)) - FilaCo
#### Performance Improvements
- (**calca**) a hit is generic code no more, takes no lock and allocates nothing (#14) (#88) - ([7332a6d](https://github.com/ide4cj/cjls/commit/7332a6de65faa1709eed1c7ec52e87bf1783b889)) - FilaCo
- (**calca**) a hit takes no gate lock and one turn of its table's lock (#80) - ([b32f12f](https://github.com/ide4cj/cjls/commit/b32f12fd36b51333542d0fa79938aac077f16ef1)) - FilaCo
- (**ginkgo**) ast accessors walk the green children, making a red node only for a match (#63) - ([42a8ef7](https://github.com/ide4cj/cjls/commit/42a8ef737f2b7fde29e24e68af0d0fdc98f761cb)) - FilaCo
#### Documentation
- (**adr**) resolution is layered as rust-analyzer's, a definition map per package (D44) (#48) (#148) - ([bdbd3d6](https://github.com/ide4cj/cjls/commit/bdbd3d6fa81ca9816d446a6803b17d4c0487dc58)) - FilaCo
- (**adr**) D16 links tree-sitter-cangjie at ide4cj, not at a fork (#135) - ([37047b1](https://github.com/ide4cj/cjls/commit/37047b1917d4856c7cf220250352ea2925ac3083)) - FilaCo
- (**adr**) note in the index that D25 rounds D24's readFloat64 correctly (#91) - ([da50444](https://github.com/ide4cj/cjls/commit/da50444db026c6f9e148652b0c4d68d4d72d69a8)) - FilaCo
- comments say what and why, not which library an idea came from (C15) (#96) - ([b965e67](https://github.com/ide4cj/cjls/commit/b965e675f773769d94b72bbf9766a01f04d39d9d)) - FilaCo
- split CLAUDE.md per module, the root one a fifth of its size (#70) - ([1d09dbb](https://github.com/ide4cj/cjls/commit/1d09dbbf9281237bb54fc1aefaaf09e97c11e000)) - FilaCo
#### Tests
- (**e2e**) Zed's capabilities among the editors', captured from Zed 1.22 (D32) (#129) - ([4837bc9](https://github.com/ide4cj/cjls/commit/4837bc95f28766aa565847267501cec496e3dde4)) - FilaCo
- (**loupe**) analysis tests as fixtures, written into the test by running them (D43) (#145) - ([273efba](https://github.com/ide4cj/cjls/commit/273efba72de7a896037ef3b9f4af60ed19206589)) - FilaCo
#### Build system
- pin the 1.3.0-alpha.20261002001050 nightly (#118) (#137) - ([25de7f5](https://github.com/ide4cj/cjls/commit/25de7f518e74d794b235b93f6ac1d4f929f88130)) - FilaCo
- unused warnings on again and fixed, off only for lsp_types and the tests (#82) - ([54be587](https://github.com/ide4cj/cjls/commit/54be5876266473efec19067af2060ab20cd4d48b)) - FilaCo
- incremental builds and tests, clean on a new compiler; CI caches target (D27) (#59) - ([e6de718](https://github.com/ide4cj/cjls/commit/e6de718395a1a16cf9084b6be25c3a425ee10f63)) - FilaCo
#### Continuous Integration
- the nightly is the pre-release nightly-build, made once and updated in place (D39) (#140) - ([e09c9a4](https://github.com/ide4cj/cjls/commit/e09c9a447bff5307c46d2c2ca125b53d6efe1d42)) - FilaCo
- one process for the server and its editor clients: a nightly, paired branches, the contract's hash (D32, #89) (#93) - ([425e7b6](https://github.com/ide4cj/cjls/commit/425e7b669d15f946d3c5eaf4c1fdd9319dfa32a4)) - FilaCo
- bump the actions group with 5 updates (#90) - ([c3df69f](https://github.com/ide4cj/cjls/commit/c3df69f8db51bdc3ed429a4d314b0df5666a1172)) - dependabot[bot]
- dependabot keeps the actions current, in one monthly PR (#76) - ([60235cd](https://github.com/ide4cj/cjls/commit/60235cd2b4d9c62cc39efdb592bfbe0e53e580fd)) - FilaCo
- fuzzing without progress report as its broken - ([95dd03e](https://github.com/ide4cj/cjls/commit/95dd03ea80c4cacd5b3b9cf1d23e94780ba7dc05)) - FilaCo
#### Miscellaneous Chores
- the Claude Code session takes LD_LIBRARY_PATH from the SDK env, for Linux (#127) - ([47e98e4](https://github.com/ide4cj/cjls/commit/47e98e437e344c60f0b0c5806a6b63c60da9a2cd)) - FilaCo

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
