# ADR-0065: A declaration of a package compiled already goes to the sources of its binary, at the position its `.cjo` gives, its name checked there

Status: accepted, 2026-10-09
Amends ADR-0038: a binary has sources to go to, never to resolve against

## Context

- Go to definition on a declaration of `std` answered nothing (#210): its `DefId` is of a `.cjo` (D38), which keeps no source, and the SDK ships none. Names resolve in the `.cjo`: fast, and exactly what cjc compiled against.
- The sources of the exact version are findable, not shipped: a nightly's release notes name its commits (`1.3.0-alpha.20261002001050`: `cangjie_runtime 5d555bcc34d6`); `std` is `stdlib/libs/std/<package>` there, 495 files, 6.2 MB. Nothing in the SDK names the commit.
- A `Decl` of a `.cjo` has `begin`, `end` and `identifierPos`: a file of `allFiles` (`std.collection/array_list.cj`, the package and the file's name), a line and a column. Measured on all of std at that nightly against that commit: every one of the 23 546 declarations with a name in the text has its name at `identifierPos`; lines and columns count from 1, columns in UTF-8 bytes, `end` past the declaration. A primary constructor's `init` is at the name of its type, a member parameter's field at the parameter, a name in backquotes inside them. Those with no name there: an enum constructor's parameters, a property's accessors (`$xget`), a `let` of a pattern, a `BuiltInDecl` (line 0), and `StdAstFormat_generated.cj`, which the build writes.
- R1 takes the sources of `std` from rustup's `rust-src` component, in the toolchain's sysroot or where `RUST_SRC_PATH` says, loads them as library roots of plain files, and never downloads them itself. Its library crates are lowered from those sources; ours are not: a match of a `.cjo` declaration to a source one is needed either way.

## Decision

- **Matched by the position of the `.cjo`** (the option taken on #210 over matching paths of names and signatures): the target is the file the `.cjo` names among the binary's sources, `begin` to `end`, its name at `identifierPos`, if the item's name is written there (inside backquotes for one written in them); nothing else. A `@When` alternative, an overload and a member of an `extend` are told apart by what cjc wrote, with no parse. Sources of another version answer nothing rather than something wrong; a fallback by names was the other way, two mechanisms for what a version mismatch alone needs.
- **Sources of a binary, not a module**: `BinaryModel.sources` (`dir` and its packages, named as a module's), `cj-project.json`'s `sources` for any binary; the analysis has their files as `Project.binarySources`, each `FileId` named as its `.cjo` names it, in no package, so nothing resolves against them. They are read with the project, as its packages' files are, with the binary's durability, and kept out of the workspace's symbols (R1's default search scope).
- **Found as the SDK is (D40)**: the first of `initializationOptions.cangjieSrc`, `CANGJIE_SRC` and `<CANGJIE_HOME>/src` that holds a directory `std`, laid out as `cangjie_runtime`'s `stdlib/libs`. In the SDK, like R1's sysroot, the sources go and come with the toolchain they are of, and need no version of their own; an SDK not writable is named by the variable or the option.
- **No network in the server**: putting the sources there is a `cjls` command of its own, by the commit the release notes give (#210's next step); a cjsdk component, when it has any, puts them in the same place.

## Consequences

- With the sources of the SDK's version, go to definition on `String`, `println`, the overload of `ArrayList.add` a call takes and a member of an `extend` of `std` goes to its source; without them, or with another version's, nothing changes.
- A load reads std's 495 files with the project's, within its budget, and parses none until one is opened.
- An opened file of the sources is a document like any other: its parse's diagnostics, and go to definition from it answers nothing, it being in no package.
- The tests read the SDK's `.cjo` against the sources at the commit `tests/corpora/fetch.py` pins (D26): a toolchain bump moves that commit too. The end-to-end job installs the SDK out of the server's environment and passes it, and the sources, in `initializationOptions`.
- Not yet: `stdx` (its sources and its commit, `cangjie_stdx`), a release SDK's commits, hover's doc comments, a type parameter of a binary declaration.
