# Changelog
All notable changes to this project will be documented in this file. See [conventional commits](https://www.conventionalcommits.org/) for commit guidelines.

- - -
## [v0.6.0](https://github.com/ide4cj/cjls/compare/82b939bfa3b95d0ce807298c2b84d29b510b0301..v0.6.0) - 2026-10-19
#### Features
- (**cjls**) a diagnostic pull answers unchanged when the report is the same (#51, D131) (#428) - ([f61d6c6](https://github.com/ide4cj/cjls/commit/f61d6c62cc6bf9fc2a4e1a2ff35e0b77661df8b8)) - FilaCo
- (**cjls**) textDocument/completion and completionItem/resolve (#203) (#362) - ([d5d5e5f](https://github.com/ide4cj/cjls/commit/d5d5e5fd74903a8c3dc87f0a18a6f42c38e92d49)) - FilaCo
- (**cjls**) expand macro, as cjls/expandMacro and as a read-only .cj.macrocall (#325) (#327) - ([8e19341](https://github.com/ide4cj/cjls/commit/8e19341f0b25cded8b02482b14c4d8dfa14a3e79)) - FilaCo
- (**cjls**) the workspace's macros built by cjc and run in the SDK's macro server (#176) (#326) - ([f5309a1](https://github.com/ide4cj/cjls/commit/f5309a1ddfa053d9441f0e5e85de6bc431f7cfa4)) - FilaCo
- (**cjls**) the server's own directory, <project>/.cache/cjls, with a layout, a cleanup and a lock (#333) (#335) - ([12ea73e](https://github.com/ide4cj/cjls/commit/12ea73e13e5ddf8364c3b212d819595dc45deec6)) - FilaCo
- (**cjls**) semantic tokens augment the client's grammar (D105) (#331) - ([8eb1515](https://github.com/ide4cj/cjls/commit/8eb1515199dbf1598c908ac5d115fc675f4fb4d6)) - FilaCo
- (**cjls**) a document opened blank is given its package line (#294) (#301) - ([2434a60](https://github.com/ide4cj/cjls/commit/2434a60b5274d62a45e2e9af701b80df9ee18eab)) - FilaCo
- (**cjsyntax**) reparse the block around an edit, for completion's marker (D110) (#350) - ([8d01b20](https://github.com/ide4cj/cjls/commit/8d01b2058cdeb86b9fa3dc1f5146a10d81c493e9)) - FilaCo
- (**loupe**) an operator none of whose candidates fits is reported at the operator (#244, D134) (#438) - ([e13eb88](https://github.com/ide4cj/cjls/commit/e13eb88e8efd3720681299349a13fe226de233ce)) - FilaCo
- (**loupe**) the members a member overrides or implements, and those overriding it (#389, D128) (#410) - ([260190e](https://github.com/ide4cj/cjls/commit/260190eb0c778047472a941ba68813aaba4112ec)) - FilaCo
- (**loupe**) references read only the files whose words name the name (#415) - ([9d99921](https://github.com/ide4cj/cjls/commit/9d999219d6b102b79b7124195a19bfc0cb3d5f0b)) - FilaCo
- (**loupe**) a test file sees std.unittest and its macros unimported, as cjc --test does (#255) (#412) - ([1a72fe1](https://github.com/ide4cj/cjls/commit/1a72fe116bdcdb28afdad98e68fa8b12c0980c3b)) - FilaCo
- (**loupe**) a generic call is solved for each combination of the overloads its arguments name (#243) (#411) - ([5ba6ef9](https://github.com/ide4cj/cjls/commit/5ba6ef9937d0f532ac52d13550cffeb82d354439)) - FilaCo
- (**loupe**) an expression macro's expansion is parsed by where its call stands and read as a file (#368) (#409) - ([5d41d84](https://github.com/ide4cj/cjls/commit/5d41d842fef7ce19dc36b2244d3b36e78063a826)) - FilaCo
- (**loupe**) completion outside a body: types, imports, keywords, overrides (#401, D127) (#407) - ([34de89a](https://github.com/ide4cj/cjls/commit/34de89a83fb4bd0addbbc0c1916f9474e4afa968)) - FilaCo
- (**loupe**) an overloaded function passed to overloads fits only those of a parameter one of it takes (#243) (#400) - ([a0bb4be](https://github.com/ide4cj/cjls/commit/a0bb4beb57a63a87dcbdf2d6a1b4f296988058cd)) - FilaCo
- (**loupe**) std's macros run in the macro server, under the calls cjls expands itself (#176, D123) (#384) - ([6108442](https://github.com/ide4cj/cjls/commit/6108442b84e5957773aae0f83f26a3bcabbef537)) - FilaCo
- (**loupe**) references across the workspace, searched where the declaration is visible (#387, D124) (#395) - ([1b86519](https://github.com/ide4cj/cjls/commit/1b86519d7f3cbdeec0c79b0da7cb4cda8ade71d0)) - FilaCo
- (**loupe**) a workspace macro called in a body is asked of the macro server, and expand macro shows it (D117) (#383) - ([c68a12e](https://github.com/ide4cj/cjls/commit/c68a12e24e9caaddca8fb9a5c11bd4d2046431dc)) - FilaCo
- (**loupe**) a lambda passed to a call that fails has parameters of why it fails (#282) (#382) - ([72f6cf0](https://github.com/ide4cj/cjls/commit/72f6cf0413a809d88583226fa3daa2de4f791d34)) - FilaCo
- (**loupe**) std.unittest's attribute arguments read as code — x in src, @Configure, @Types (#191, D115) (#372) - ([3d3961a](https://github.com/ide4cj/cjls/commit/3d3961ae6c892785e7177b49ee21090ec06990fa)) - FilaCo
- (**loupe**) hover on the names of an import and on a package (#379) - ([012af48](https://github.com/ide4cj/cjls/commit/012af4814921aeefe7225a1cf4c47127efe145b5)) - FilaCo
- (**loupe**) a body cjls writes in an expansion of its own is a comment naming the macro (D118) (#376) - ([0ed05b6](https://github.com/ide4cj/cjls/commit/0ed05b6249f2932ba3acd3d98ce97ebf7145a74c)) - FilaCo
- (**loupe**) a quote's interpolations read as code of the macro (#195, D116) (#366) - ([41b4fbb](https://github.com/ide4cj/cjls/commit/41b4fbb0ff1296d1d2bc5d74f57ba0f7089ec9f3)) - FilaCo
- (**loupe**) expand macro in a whole declaration, hover on a macro call, @Derive in a workspace macro's input (D114) (#360) - ([1f26204](https://github.com/ide4cj/cjls/commit/1f262044f9fbc0bc35605478335044b9aa60051a)) - FilaCo
- (**loupe**) completions at a cursor, members after a dot and names in scope (#203, D111) (#352) - ([d551ebe](https://github.com/ide4cj/cjls/commit/d551ebe15261556fa8749367c97ba342facd36ee)) - FilaCo
- (**loupe**) a call's arguments matched to each candidate's parameters before it is tried (D110) (#254) (#351) - ([82acceb](https://github.com/ide4cj/cjls/commit/82acceb56f1116382b8fcbbd26e1d86116494c21)) - FilaCo
- (**loupe**) go to definition on imports and packages; hover shows the docs and interfaces macros hide (#348) - ([8028633](https://github.com/ide4cj/cjls/commit/802863327434e627409798f1f3614b2fcc2e953b)) - FilaCo
- (**loupe**) hover tells what the language builds in, from the Cangjie docs (#344) (#347) - ([86ef4dd](https://github.com/ide4cj/cjls/commit/86ef4ddb4db8ae25f64375d49a956dcdaeca340d)) - FilaCo
- (**loupe**) the macro server's answers as an input, and the requests for them (#176) (#314) - ([d79aed1](https://github.com/ide4cj/cjls/commit/d79aed199badc77f2c8199a14fa67e2a01feb653)) - FilaCo
- (**loupe**) @When evaluated against the package's cfg, inactive code greyed (#149) (#302) - ([ca1bf93](https://github.com/ide4cj/cjls/commit/ca1bf93c316f473aaa6af9522aba07ecfa329c6d)) - FilaCo
- (**loupe**) mismatches and counts of arguments reported, the diagnostics gate (#53) (#296) - ([4d7a016](https://github.com/ide4cj/cjls/commit/4d7a01691bdd42831d17a57c410a9a79db9b06c4)) - FilaCo
- (**macro_server**) cjsyntax's tokens as cjc's, numbered by the SDK's Tokens.inc (#176) (#305) - ([6718d6a](https://github.com/ide4cj/cjls/commit/6718d6ab2a329711b679f0dd2aa23e1db65ad097)) - FilaCo
- (**macro_server**) the SDK's LSPMacroServer driven over its own protocol (#176) (#295) - ([82b939b](https://github.com/ide4cj/cjls/commit/82b939bfa3b95d0ce807298c2b84d29b510b0301)) - FilaCo
- (**project_model**) multiplatform source sets and common/specific (#318) (#323) - ([90fa6b2](https://github.com/ide4cj/cjls/commit/90fa6b25209d535d2563cce808ec53eff894b275)) - FilaCo
#### Bug Fixes
- (**ci**) run cjc behind a shim that closes inherited descriptors (#342, D125) (#394) - ([78abaff](https://github.com/ide4cj/cjls/commit/78abaff3d0ff8336c2ed1ffd650ee56d6bd7025c)) - FilaCo
- (**cjls**) a read-only request the files changed under runs again on a fresh snapshot (D122) (#381) - ([a1f088f](https://github.com/ide4cj/cjls/commit/a1f088fa5292cb1d04880773f1e006ea70c63406)) - FilaCo
- (**cjls**) cjc links a macro library on macOS without envsetup's SDKROOT (#361) - ([36eef08](https://github.com/ide4cj/cjls/commit/36eef08a34d5165d4cce8313a93c49b0d22da047)) - FilaCo
- (**cjls**) give way before stdin's read blocks, so a request's spawn starts (#324) (#330) - ([e18df1f](https://github.com/ide4cj/cjls/commit/e18df1f1a79d43ba7bc49abc8aa7f100ae20bf52)) - FilaCo
- (**cjls**) diagnostics pulled again after another file changes (D100) (#317) - ([46a87a6](https://github.com/ide4cj/cjls/commit/46a87a6c10935f59ff758c341e94e4c0ceb531a6)) - FilaCo
- (**loupe**) an item the macro server's output replaces is checked in that output alone (D132) (#439) - ([a8f8ddd](https://github.com/ide4cj/cjls/commit/a8f8ddd2fbd1f0e781cb5199807b1f38b3ca3d64)) - FilaCo
- (**loupe**) hover shows what @Derive/@DeriveExt add once the macro server expanded them (#430) - ([40c3b50](https://github.com/ide4cj/cjls/commit/40c3b50adb08ec7cdad7a5c185661aa12d00602f)) - FilaCo
- (**loupe**) a file that is no test sees no constructor only a test imports (#429) - ([b3d8d1c](https://github.com/ide4cj/cjls/commit/b3d8d1c27a0ccb186eb41cd1bdfc867a6f4b8eb8)) - FilaCo
- (**loupe**) a name after an enum's constructors lists the member keywords (#427) - ([eebb59f](https://github.com/ide4cj/cjls/commit/eebb59f180abf7a50c0c24d3f1ce0c7be4262c3e)) - FilaCo
- (**loupe**) completion lists no operator function as a member (#419) - ([b5e8e00](https://github.com/ide4cj/cjls/commit/b5e8e006b36c519e9ab098be4c327cfd353a066a)) - FilaCo
- (**loupe**) a type parameter's declaring name means the type parameter (#398) (#416) - ([5488198](https://github.com/ide4cj/cjls/commit/54881981a25fbca979890b84c908bc4a69c32241)) - FilaCo
- (**loupe**) a parameter in a macro call is a parameter of its declaration (#413) - ([5a2c198](https://github.com/ide4cj/cjls/commit/5a2c198936415f56d62383747d28e21bb65cd715)) - FilaCo
- (**loupe**) doc comments and macro calls on primary constructor parameters (#377, #357) (#380) - ([b4bf468](https://github.com/ide4cj/cjls/commit/b4bf468fecc47ee8b77867eafd0b397cbd08160a)) - FilaCo
- (**loupe**) macro attributes keep nested brackets; go to definition picks the macro overload a call runs (#349) - ([3d69914](https://github.com/ide4cj/cjls/commit/3d69914b8a824d575de0870ee2e273e479ed3f09)) - FilaCo
- (**loupe**) a file of no package finds lang items in the SDK's std.core, as it finds a builtin type's extends (#319) (#321) - ([4d6cbc6](https://github.com/ide4cj/cjls/commit/4d6cbc6b3883e18150114bdd864d2a076a5cf6a0)) - FilaCo
- (**loupe**) the false mismatches the gate found on std's sources (#287) (#303) - ([677e146](https://github.com/ide4cj/cjls/commit/677e146330c1b987ab813cf29f42943101123885)) - FilaCo
- (**macro_host**) each macro package built into its own project's macro-build (#338) (#408) - ([2600250](https://github.com/ide4cj/cjls/commit/2600250c0b5abf20096c074d7993128dfcb58e99)) - FilaCo
- (**macro_server**) the server loads its own SDK's libraries before inherited ones (#310) (#414) - ([af391d7](https://github.com/ide4cj/cjls/commit/af391d7dd11ffb64ade997f9b210f164a18ac563)) - FilaCo
- (**project_model**) the macros' error roots held by D108's gate, which merged before them (#343) - ([4f9021a](https://github.com/ide4cj/cjls/commit/4f9021a0d9ee244d6f9583218fb2c151aa508ee5)) - FilaCo
- (**rope**) lineStart and lineEnd throw for a line outside the text (#426) - ([60a490c](https://github.com/ide4cj/cjls/commit/60a490ceaa525dd8eb3a03a6e7c7305d4b0d2110)) - FilaCo
#### Documentation
- (**adr**) semantic tokens are sent whole, no full/delta (D136) (#442) - ([b369d97](https://github.com/ide4cj/cjls/commit/b369d9772051501276c8d5491027c1d5fdb756c4)) - FilaCo
- (**adr**) workspace/diagnostic is not offered (D135) (#440) - ([9ca2d12](https://github.com/ide4cj/cjls/commit/9ca2d12d19119c15fb1f83ad3d0b6b38a3fa0736)) - FilaCo
- (**adr**) a client's version is the pinned cjls's minor with a patch of its own (D133) (#436) - ([4f4d1b8](https://github.com/ide4cj/cjls/commit/4f4d1b8fdbc7fc12cb54a0292348b028c80c95bf)) - FilaCo
- (**adr**) an item a macro's output replaces is read through that output alone (D132) (#435) - ([05d7115](https://github.com/ide4cj/cjls/commit/05d711536f538f8178d961c7bdbb2385e4306d82)) - FilaCo
- (**adr**) expression macros, std.unittest's included, asked with the file's calls and read while current (D117) (#374) - ([86f6fc7](https://github.com/ide4cj/cjls/commit/86f6fc717240f08791c5cdcbfeef6629c0e8af8f)) - FilaCo
- (**adr**) a client's settings are made again when its pin moves, never checked against the cjls under test (D107) (#336) - ([69c1f7f](https://github.com/ide4cj/cjls/commit/69c1f7f9ae767523d903b08274e05fd18081783b)) - FilaCo
- (**adr**) one release supports a window of SDKs (D94) (#304) - ([e75c37a](https://github.com/ide4cj/cjls/commit/e75c37a8dffc9ea4dc0e685cf6d42db05802ddf0)) - FilaCo
- (**prior-art**) R9 tried again: it builds and answers, slowly (#22) (#329) - ([5305006](https://github.com/ide4cj/cjls/commit/5305006bedaef6e3f3971dfecec8bd70d6057a3f)) - FilaCo
- the code style follows std where the compiler leaves a choice, checked by cjlint (D126) (#396) - ([82f875c](https://github.com/ide4cj/cjls/commit/82f875c8054c1ba15b4e439ecff571b1fc3b2e13)) - FilaCo
#### Tests
- (**cjls**) a macro past its deadline is tested on deadlines fired by hand (#373) - ([e445b21](https://github.com/ide4cj/cjls/commit/e445b218cd14799aa82fbfc332714a041606490d)) - FilaCo
- (**e2e**) the overload of go to definition picked with an SDK or without (#320) - ([a321ae5](https://github.com/ide4cj/cjls/commit/a321ae52bb619bd2c0fefcac459ce060018fef98)) - FilaCo
- (**loupe**) a trailing lambda goes to a named last parameter past ones of a default value (#280) (#392) - ([4296ee3](https://github.com/ide4cj/cjls/commit/4296ee3e8d7295ea8d7a56079beabd44ae366d2a)) - FilaCo
- (**loupe**) a call the analysis cannot type in an argument leaves its candidate undecided (#281) (#364) - ([245ae2d](https://github.com/ide4cj/cjls/commit/245ae2d1b5e8a0c423c783d30abd8faba0dfda3b)) - FilaCo
- (**loupe**) cases over a list of inputs are parameterized (#363) - ([bbc288a](https://github.com/ide4cj/cjls/commit/bbc288acb748ede42ef6de86d68eaf441f2e333d)) - FilaCo
- (**loupe**) a result keeping its evicted tree is told by the tree it holds, not by a weak reference (#316) - ([60b7ac0](https://github.com/ide4cj/cjls/commit/60b7ac0c89155851e41acdfd841705654af5cd37)) - FilaCo
- (**loupe**) a variadic function of a .cjo, called with its array's elements (#315) - ([1f1be1e](https://github.com/ide4cj/cjls/commit/1f1be1ee9adbc818d56fe92f558f3b309a70dd08)) - FilaCo
- (**project_model**) this repository's error roots held to a count that only shrinks (D108) (#341) - ([a9ee0ec](https://github.com/ide4cj/cjls/commit/a9ee0ec4282ef985eaf0c3f3754ba5ad5ded7683)) - FilaCo
#### Build system
- (**githooks**) pre-push runs cjc behind CI's shim (#342) (#399) - ([05dca1d](https://github.com/ide4cj/cjls/commit/05dca1da4261f2df82ff36bc0028f70b62004063)) - FilaCo
- (**githooks**) pre-push checks the format as CI's Format job does (#378) - ([dfcd812](https://github.com/ide4cj/cjls/commit/dfcd81205744a707024b0963c1a386b8b05c7837)) - FilaCo
- pin the 1.3.0-alpha.20261014001050 nightly (#355) - ([b25c503](https://github.com/ide4cj/cjls/commit/b25c503cffdfcc033783cc65a0519d257b0248ba)) - FilaCo
- the unused warnings off in every module, the dead names they found removed (D97) (#313) - ([61cc934](https://github.com/ide4cj/cjls/commit/61cc934371e3ec9531a1d2f5c00ba535e03f85d0)) - FilaCo
#### Continuous Integration
- (**coverage**) the gate is tagged out of the coverage run, fixtures for what it alone reached (D120) (#385) - ([42958b8](https://github.com/ide4cj/cjls/commit/42958b8d63a70a9b8822e857698323eac785b432)) - FilaCo
- hold every Cangjie file to cjls fmt (#356) - ([d956089](https://github.com/ide4cj/cjls/commit/d9560896302a50c10bbbed878e2d0c5af5b2551e)) - FilaCo
- build the binary and run the tests in two jobs side by side, each with its own cache (D96) (#312) - ([eed2d7a](https://github.com/ide4cj/cjls/commit/eed2d7a3a41750beb567d74184740d3ce774bb45)) - FilaCo
#### Refactoring
- (**macro_host**) the macro host is a library module, cjls keeps only the thread that drives it (#393) - ([27d1513](https://github.com/ide4cj/cjls/commit/27d1513421f9a4ac69b1ec5ac37889d89f479d96)) - FilaCo
- (**platform**) hostArch is the one @When of the code, files named for what they hold (D113) (#354) - ([ecaa70a](https://github.com/ide4cj/cjls/commit/ecaa70ad87291ae01b6f7eccaf37a4f792e614ea)) - FilaCo

- - -

## [v0.5.0](https://github.com/ide4cj/cjls/compare/326917edeee72edeba9216d1357c1a4deb626cb6..v0.5.0) - 2026-10-12
#### Features
- (**cjls**) an open document in no loaded package finds its own project (#265) (#291) - ([c4d0eb9](https://github.com/ide4cj/cjls/commit/c4d0eb9950d1fbbf7097f28c097148da88004dff)) - FilaCo
- (**cjls**) a document opened among the files a loose root left out is analyzed (#213) (#260) - ([13932ce](https://github.com/ide4cj/cjls/commit/13932ce9d85ec2d7e984e54f84fe77d288d9fc67)) - FilaCo
- (**cjls**) settings from initializationOptions, workspace/configuration and didChangeConfiguration, their schema by cjls --config-schema (#259) - ([cab89e0](https://github.com/ide4cj/cjls/commit/cab89e0d35b68de961e7418954bd472ad340cbde)) - FilaCo
- (**cjls**) on Windows, the server's child dies with its parent (#258) - ([ba0a7ad](https://github.com/ide4cj/cjls/commit/ba0a7adc3777bc6ebacd9a045bcbb3161485a25e)) - FilaCo
- (**cjls**) textDocument/rangeFormatting, the whole file's edits on the lines a range covers (#237) - ([d80bb3b](https://github.com/ide4cj/cjls/commit/d80bb3b17b420980bffe69725fdd4fb077ff9198)) - FilaCo
- (**cjls**) `cjls fetch-src` puts std's sources of the SDK's nightly into its src (#210) (#224) - ([29817ea](https://github.com/ide4cj/cjls/commit/29817eaa03028b7a02f8e6cc2af24b478a7daa1e)) - FilaCo
- (**cjls**) the .cjo of the binaries are watched, and an update read without a restart (#141) (#220) - ([c09d4fa](https://github.com/ide4cj/cjls/commit/c09d4fa5b65cb5a0a7ffb796da0a722cb5fd4bdb)) - FilaCo
- (**loupe**) an extend of a type alias extends the type it expands to (#277) (#290) - ([e774a31](https://github.com/ide4cj/cjls/commit/e774a314f8fdd3c93d44d45a8751074e4d70b4d8)) - FilaCo
- (**loupe**) a type a macro not read is called on may have any supertype (#175) (#288) - ([2bfb758](https://github.com/ide4cj/cjls/commit/2bfb758f3dd057d22a10cce3d25894e03bec0c3d)) - FilaCo
- (**loupe**) what std.unittest's macros declare, as expansions (#175) (#264) - ([95e3f8c](https://github.com/ide4cj/cjls/commit/95e3f8c1f2e67c419889b9809585b4279cb2f0b0)) - FilaCo
- (**loupe**) semantic tokens tell names at their use by what they mean (#229) - ([10ec426](https://github.com/ide4cj/cjls/commit/10ec4266df3444915452dcfd913cd768fb0e7b2f)) - FilaCo
- (**loupe**) a type not known is an error or what the analysis cannot find, a qualifier no value (#53) (#257) - ([955b329](https://github.com/ide4cj/cjls/commit/955b3291a1bd66fdf5b0bc3cde62f65aefed61aa)) - FilaCo
- (**loupe**) optional chains lowered into the matches cjc desugars them to, Some and None lang items (D70) (#228) - ([b1ce907](https://github.com/ide4cj/cjls/commit/b1ce907578997f008324303bad055720e221ea41)) - FilaCo
- (**loupe**) document highlight, the names of a file meaning what one does (#200) (#223) - ([72f6307](https://github.com/ide4cj/cjls/commit/72f630744b2b99d05a7900f03955ed3ba344c4f7)) - FilaCo
- (**loupe**) hover shows a declaration's signature and docs, a value's inferred type (#199) (#222) - ([3b37855](https://github.com/ide4cj/cjls/commit/3b378558cb2ca528ef5bd1e9f671c5c2450489e3)) - FilaCo
- (**loupe**) what std's @Derive adds, an expansion read as any file (#175) (#221) - ([5c48668](https://github.com/ide4cj/cjls/commit/5c4866889e0f690a2ab649a38b91d5a252c55b83)) - FilaCo
- (**loupe**) coalescing, pipelines and compositions typed as cjc desugars them, std.core named through lang items (D66) (#48) (#217) - ([6a675b7](https://github.com/ide4cj/cjls/commit/6a675b78e3ef3fab4652f58dbffcca9971248e8b)) - FilaCo
- (**loupe**) go to definition into std's sources, at the positions of its .cjo (#210) (#215) - ([e6afb9a](https://github.com/ide4cj/cjls/commit/e6afb9adeec8ffcd4f18cc0570b6e03a1b24d84c)) - FilaCo
- (**loupe**) an operator of a type is a call of its member, the language's own tried first (D64) (#48) (#198) - ([a093cb1](https://github.com/ide4cj/cjls/commit/a093cb1d42cfa9d8fa66ca1251128a7135cf5f30)) - FilaCo
- (**loupe**) macro names resolved through imports (#175) (#197) - ([d36f454](https://github.com/ide4cj/cjls/commit/d36f454132604cce2ecd8fa7072bae035e8958cf)) - FilaCo
- (**lsp_codegen**) codecs for the requests the server sends, and registrations typed per method (#208) - ([a33cf12](https://github.com/ide4cj/cjls/commit/a33cf12cd5464b0dafb85d1ca20e8a4557bf109c)) - FilaCo
- (**project_model**) loose files with a main each are programs of their own (#211) (#219) - ([9a05b43](https://github.com/ide4cj/cjls/commit/9a05b43aebcdc8ea8a06ada4cec778e734f57010)) - FilaCo
#### Bug Fixes
- (**calca**) an input created in a batch is stamped with the revision before it, and an appended declaration runs no body again (#262) (#289) - ([fc3aa06](https://github.com/ide4cj/cjls/commit/fc3aa060b8ecdc683442c11d040bd17ce97f4c88)) - FilaCo
- (**calca**) a write that changes no input opens no revision (#233) - ([f612d76](https://github.com/ide4cj/cjls/commit/f612d76807a3d0807ab0bdaf1d22759263c2fa5d)) - FilaCo
- (**cjformat**) a body's `{` on a line of its own joins the line before (#252) - ([bc98a04](https://github.com/ide4cj/cjls/commit/bc98a049013e00c3edfceb4467aa070ad66faf69)) - FilaCo
- (**cjls**) the load-progress test sets std's sources through Settings (#274) - ([a75fc17](https://github.com/ide4cj/cjls/commit/a75fc17e63e40beec4f4e0d1d3d08cdcbb52467b)) - FilaCo
- (**cjls**) a change of workspace folders is one revision (S12) (#207) - ([87ec1be](https://github.com/ide4cj/cjls/commit/87ec1bef2c00a76c4ca939c09d747393de2b301b)) - FilaCo
- (**cjsyntax**) a declaration in macro calls has the comments before them as its docs (#231) - ([5cdb4c3](https://github.com/ide4cj/cjls/commit/5cdb4c34792942e7443707b68b71572f7feecedc)) - FilaCo
- (**docs**) an open pull request clashes only by the ADRs it adds, not by master's (#232) - ([9e41b01](https://github.com/ide4cj/cjls/commit/9e41b015479748fdc8a7957a86dcb4da621ad113)) - FilaCo
- (**loupe**) a member named through its type or alone is the one cjc takes (#266) - ([5b78194](https://github.com/ide4cj/cjls/commit/5b78194e208b53e5cee971de4a8d3174df2b25c6)) - FilaCo
- (**loupe**) a type parameter's hover shows its bounds, or nothing (#236) - ([960c881](https://github.com/ide4cj/cjls/commit/960c8815697cab3131a238d545f5c4671c954d20)) - FilaCo
- (**project_model**) cjsdk's default toolchain is found through its link, a cjc with no SDK around it is passed over (#194) - ([326917e](https://github.com/ide4cj/cjls/commit/326917edeee72edeba9216d1357c1a4deb626cb6)) - FilaCo
#### Performance Improvements
- (**calca**) a dependency keeps its memo's entry or interned slot, and answers from it without a lock (#269) - ([2df0749](https://github.com/ide4cj/cjls/commit/2df074900f7cffd1395d49399a78fd796a8dc7d2)) - FilaCo
- (**fjson**) a union reads its value on the rewound reader, no slice and no second reader (#225) - ([ac29c7c](https://github.com/ide4cj/cjls/commit/ac29c7c24c25258d03ce9ef8a28e443978ae809a)) - FilaCo
- (**jsonrpc**) params are read in place when the method came first, by the route's own reader (D73) (#230) - ([9568779](https://github.com/ide4cj/cjls/commit/95687793726fb8a86818e4d976544649b5ef0efa)) - FilaCo
#### Documentation
- (**adr**) the workspace's macros run in the SDK's LSPMacroServer (D87) (#284) - ([6b9b99a](https://github.com/ide4cj/cjls/commit/6b9b99ad004d4f916785a3f839e72443b6dc0623)) - FilaCo
- (**adr**) JSON is read by the pull reader, not through a tape index (D86) (#270) - ([75d160c](https://github.com/ide4cj/cjls/commit/75d160c7ea9e4c2630ab96642982bdf61d72ab1a)) - FilaCo
- (**adr**) what a name means is kept where it was resolved (D84) (#267) - ([afbc02a](https://github.com/ide4cj/cjls/commit/afbc02a2c7e10e9afd8361099a22455128612cb4)) - FilaCo
- (**prior-art**) cjls's column as master has it, calca's accumulators decided against (#286) - ([605d5c0](https://github.com/ide4cj/cjls/commit/605d5c0f1c108b1d86d8b7c4f10fbe9dafc2b556)) - FilaCo
- (**prior-art**) how R1, R2, R3, R6 and R7 report semantic errors and keep them from cascading (#238) - ([9fff4cd](https://github.com/ide4cj/cjls/commit/9fff4cd1e0b9fa54807d07670aebd0da54da4cca)) - FilaCo
#### Tests
- (**cjls**) the runtime's used heap is not held to its limit (#234) - ([2e04993](https://github.com/ide4cj/cjls/commit/2e0499373d63db2000d5d711a39f9a139356c99b)) - FilaCo
- (**perf**) scenarios for definition, hover and completion, and a threshold on queries executed (#261) - ([0c2ca52](https://github.com/ide4cj/cjls/commit/0c2ca52c0aa34f8763327b6d02d4f0a04804039f)) - FilaCo
- (**perf**) cjls is ready when its load's progress ends, not at its initialize answer (#209) - ([26df290](https://github.com/ide4cj/cjls/commit/26df29052af17b69070659c9f9ee7f3f72f1cb89)) - FilaCo
#### Refactoring
- (**loupe**) inference looks a value's members up on its type (#275) - ([54b01a5](https://github.com/ide4cj/cjls/commit/54b01a5880031a1b7211797a3e1e54582a158bb5)) - FilaCo

- - -

## [v0.4.0](https://github.com/ide4cj/cjls/compare/30584a34c189f21d29921d1badf83077a8bf36c1..v0.4.0) - 2026-10-08
#### Features
- (**cjformat**) a formatter of our own on the syntax tree, as textDocument/formatting and cjls fmt (#184) - ([d779a48](https://github.com/ide4cj/cjls/commit/d779a48f70f39605dd22a36d166a5978d45aa1cb)) - FilaCo
- (**cjls**) selection ranges from the syntax tree (#42) (#186) - ([38586ea](https://github.com/ide4cj/cjls/commit/38586ea35f578b2687926d68b0b867294cc8033f)) - FilaCo
- (**cjls**) the workspace loaded on a spawn, in batches between the messages, reporting $/progress (#84) (#183) - ([d5c3daa](https://github.com/ide4cj/cjls/commit/d5c3daab6d3d634efe5fdd664a48fa0a3d226b4d)) - FilaCo
- (**cjls**) textDocument/definition from definitionAt (#169) (#178) - ([66e5e4e](https://github.com/ide4cj/cjls/commit/66e5e4e39018ced8b7e305ab0e8c57184618ff30)) - FilaCo
- (**loupe**) an overload taken by trying each candidate, the nearest level first, the most specific (D63) (#48) (#185) - ([156af2d](https://github.com/ide4cj/cjls/commit/156af2d3d2a2f879b6dcf2c93778030d74a6d3cc)) - FilaCo
- (**loupe**) an expression macro's arguments parsed as an argument list and resolved before expansion (#174) (#182) - ([1a2d61a](https://github.com/ide4cj/cjls/commit/1a2d61a4de29b16bcb559c66e544d04056ba8135)) - FilaCo
- (**loupe**) folding ranges from the syntax tree, textDocument/foldingRange (#41) (#180) - ([f1337e8](https://github.com/ide4cj/cjls/commit/f1337e893959fdbcb731a825822d835201c85b2a)) - FilaCo
- (**loupe**) type arguments not written inferred per call, as cjc's local synthesis (D57) (#48) (#177) - ([6a525c5](https://github.com/ide4cj/cjls/commit/6a525c52e2cae8022d15702e5176b68821fd3216)) - FilaCo
- (**loupe**) a body's types inferred locally in one query, a member of a value looked up from its type (D55) (#48) (#168) - ([c9fec2d](https://github.com/ide4cj/cjls/commit/c9fec2d57db54b1adafef2cef7139c10c0ebaba3)) - FilaCo
- (**loupe**) a type an interned Ty, a declaration signature lowered to it, of a source or a .cjo (D54) (#48) (#163) - ([db23b75](https://github.com/ide4cj/cjls/commit/db23b75045ce6e08268652e686dcc67c1c1ca0d7)) - FilaCo
- (**loupe**) the extends a file may see looked for in its interfaces' packages, those it sees chosen at the lookup (D53) (#48) (#161) - ([9585362](https://github.com/ide4cj/cjls/commit/958536294d1cfdc6c83575867f3aae254b69fa2c)) - FilaCo
- (**loupe**) a name after a dot resolved by names up to a value, members looked up from a type (D52) (#48) (#160) - ([9f0d522](https://github.com/ide4cj/cjls/commit/9f0d522df52eaf19fafd947f32d96a471d95eda8)) - FilaCo
- (**loupe**) a body lowered to HIR, its scopes, and what a name in it means (D49) (#48) (#156) - ([9c44137](https://github.com/ide4cj/cjls/commit/9c4413758dbb16d127abf71223a63f3e7fe3ff48)) - FilaCo
- (**loupe**) a signature a query of its declaration, the paths in its types resolved (D48) (#48) (#153) - ([b4a4671](https://github.com/ide4cj/cjls/commit/b4a4671fa9cf54f91e099c43a3be15b6de7f2a7c)) - FilaCo
- (**loupe**) a file's scope, the prelude a glob of every file, globs read at the lookup (D47) (#48) (#152) - ([af1187e](https://github.com/ide4cj/cjls/commit/af1187ea90227fdf72a294e5f691cb1bd664716b)) - FilaCo
- (**loupe**) imports resolve down the packages, a package's exports (D46) (#48) (#151) - ([30584a3](https://github.com/ide4cj/cjls/commit/30584a34c189f21d29921d1badf83077a8bf36c1)) - FilaCo
#### Bug Fixes
- (**ci**) the nightly filters CI's runs for success itself, scheduled off the hour (#158) - ([08c0cd0](https://github.com/ide4cj/cjls/commit/08c0cd048b67c453c4c226e055e94194d30060ed)) - FilaCo
- (**cjls**) a folder come or gone is watched and followed, as VS Code reports it as one event (D58) (#94) (#181) - ([5f1cea4](https://github.com/ide4cj/cjls/commit/5f1cea400e5027dbf6b19a5c02d0166083e2da88)) - FilaCo
- (**cjls**) a document whose diagnostics throw no longer stops the push of the ones after it (#162) - ([ba642ce](https://github.com/ide4cj/cjls/commit/ba642ce88249b2368b4dd49a884574ef7084854c)) - FilaCo
- (**jsonrpc**) the end of input cancels what is in flight, a frame over the limit is answered and skipped (#109) (#179) - ([fc32f54](https://github.com/ide4cj/cjls/commit/fc32f5481d959cd1a360d5d1bd764e87903ff3b3)) - FilaCo
#### Documentation
- (**adr**) the ADR index written after the merge by a bot, an id taken once (D56) (#147) (#173) - ([8311d1f](https://github.com/ide4cj/cjls/commit/8311d1f27314aafb3a048b13c6295d250271dd50)) - FilaCo
#### Tests
- (**cjls**) what the server advertises checked against its routes, a file's path from the snapshot (#106) (#165) - ([3d08b0a](https://github.com/ide4cj/cjls/commit/3d08b0a48891933c23e12e4d349144e3e7631699)) - FilaCo
#### Build system
- -O2 a release option, the coverage built with -g and no warning (D51) (#157) - ([33cb913](https://github.com/ide4cj/cjls/commit/33cb913a9fbab5d1017fb830b02c92b201fc3913)) - FilaCo
#### Continuous Integration
- the toolchain from the GitHub mirror, checked against sha256 pinned from gitcode (D62) (#190) - ([975a6b3](https://github.com/ide4cj/cjls/commit/975a6b3715f26b973cccc0c9f176180e4dfd6fd4)) - FilaCo
- code coverage of the workspace with cjcov, shown as a README badge (#155) - ([6ea8f21](https://github.com/ide4cj/cjls/commit/6ea8f21eedd7cd801851c5dc7ea0a23cbb64688e)) - Valerie
#### Miscellaneous Chores
- (**claude**) merged worktrees pruned at session start, a Sonnet scout agent, a change-coverage skill (#167) - ([0f0605b](https://github.com/ide4cj/cjls/commit/0f0605b205faca4dc67833aa2b7886da592019e3)) - FilaCo

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
