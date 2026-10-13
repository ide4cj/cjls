# ADR-0109: std's macros run in the macro server from the SDK's libraries, under the calls cjls expands itself

Status: proposed
Amends ADR-0098: a call of std's macro is a call the server runs, nested or read like a workspace macro's
## Context

- #176 decided that once the server runs, it runs std's macros as well. Its real output replaces cjls's own expansion (#175) under the same `MacroCallId`. Ours stands until the server answers, and whenever it cannot (#176's first comment, D87's last consequence).
- The SDK ships std's macros compiled, beside its runtime: `runtime/lib/<target>/libcangjie-std-deriving.so` (`.dylib`, `.dll`), `libcangjie-std-unittest.testmacro.so`. The name is the package's, its first `.` as `-`. They export the functions cjc names a macro by, `macroCall_a_Derive_std_deriving` (checked with `nm -D` on 1.3.0-alpha.20261002, Linux; the Windows runtime ships the same `.dll`s). Nothing has to be built.
- After D98 a call is the server's when its macro is declared in a source package. std's macros resolve to a `.cjo`, so their calls stayed as written in the input of a workspace call around them, and the host did nothing without a workspace macro package. It did not even look for the SDK, which it found only to build.
- `MacroCallId` is already (file, item, index of the call on the item), the same for #175's expansion and the server's.
- Inference reports what it finds in the bodies of source files only, never in an expansion's (`loupe.diagnostics`). The bodies the real output brings are read for names and types, but nothing is reported in them.

## Decision

- **A call of a macro of std is a call the server runs** (`serverCalls`, `ServerMacro`), as a workspace macro's is: in cjc's order, innermost first, and the outermost one on a top-level item is read. A macro's package is a source package of the workspace or a package of std (`MacroPackage`).
  - A call of std on a member is the server's only under a top-level item with a call the server runs. Its output is then part of that call's input (`@DeriveExclude`, `@TestCase` under `@Derive`, `@Test`). On a member of any other item, nothing would read it.
  - A workspace call around a call of std waits for that call's output, as it waits for a nested workspace call's.
- **The output read replaces the analysis's own expansions on its item** (`expandedCalls`). Until there is one, and whenever a run failed with no expansion before it, #175's own expansions of the item stand. A macro's own errors come with the run (`macroDiagnostics`).
- **std's macros run in a server of their own**, beside the workspace's (`MacroServers`), each guarded as D104 says. On this repository, the SDK's runtime aborts (SIGABRT) the process that loads `libcangjie-std-deriving.so` for the first time after one `@CalcaTracked` of `lib-macro_calca.macros.so` ran in it (the one on `parkedSize` in `calca/src/claim_test.cj`; the two calls replayed alone abort it every time, the library loaded first does not). Apart, a rebuilt library of the workspace restarts only its own server, and a workspace macro that ends its server costs std's calls nothing.
- **std's library is the SDK's, found by the package's name** (`MacroServerPaths.stdMacroLibrary`). A call whose package has no library there is never sent (D87). Its stamp in the request's fingerprint is a hash of the package's `.cjo`, which another SDK changes.
- **The host runs without a workspace macro package.** It looks for the SDK itself once a call is waiting, not only to build, and not before: a workspace with no macro call starts no process.
- **An expansion the server made is of kind `server`** in `cjls/expandMacro` (D103), whoever declared its macro. cjls's own is `cjls`, as before.

## Consequences

- The first load of a workspace asks the server for every call of std, one round trip each (306 `@Derive` in this repository alone). #176's step 5 measures it.
- The real output's bodies are read but their type errors are not reported (#53).
- A workspace call around a call of std is not asked while the SDK has no library for it. Before, it was asked with the call of std left as written.
- When std's macros generate other declarations than #175's expander, the server's win wherever it answered. `StdExpansionDriftTest` holds every case #175 expands to what the SDK's std declares, header by header, annotations and the order of modifiers aside: a nightly that changes them fails it. Where cjls declares by design otherwise (`@Test` rewrites its class, which an expansion after the item cannot), the difference is listed, and the list only shrinks.
