# SDK issues and retained workarounds

This is the canonical registry requested by [#332](https://github.com/ide4cj/cjls/issues/332).
It records defects separately from language rules and development procedures.
For SDK selection and runnable checks, use [Development](development.md).
Historical ADRs retain their original observations and decisions.

The pin at this audit is `1.3.0-alpha.20261014001050`; the authoritative value is
[`.cangjie-version`](../.cangjie-version). **None of these defects was reproduced
or declared fixed during this documentation audit; K4 includes verification
recorded separately in PR #457.** K19, K27 and K28 record subsequent observations;
K26 records a scoped workaround from PR #477. A historical observation
is not evidence that a defect still reproduces on the pin, nor that it is fixed.
An unspecified version/platform below is explicitly unverified, not all versions
or all platforms. Dates abbreviated as `20260918` refer to nightly build dates;
exact build timestamps are unknown unless given.

Entries are **open** (fix status unverified), except K4, whose original scenario
no longer reproduces on the pinned SDK on Linux x86_64 (PR #457). An entry with no
workaround or no known affected cjls path is retained as a reported SDK risk, not
a new coding restriction. Upstream report URLs are **unrecorded for every entry**:
repository issues and PRs below are local evidence, not upstream SDK reports.
The maintainer files upstream reports. Preserve current workarounds unless focused
evidence justifies retiring them on the relevant SDK/platform; K4 records a
requirement already retired in master.

Retired entries are struck through in the index and heading, with the verified
SDK/platform scope and evidence retained below. Keep their IDs and anchors for
existing references; never reuse an ID. Apply this convention to any entry once
focused verification supports retiring its restriction. An implemented workaround
or a passing ordinary test run alone does not establish an SDK fix.

## Index

| ID | Problem | cjls response |
|---|---|---|
| [K1](#k1) | Spawn immediately before blocking FFI may never start | Yield before stdin read |
| [K2](#k2) | Known libc names implicitly become fast native calls | Use `readv`, preserve C5 |
| [K3](#k3) | std stdin read waits for full buffer/EOF | Read stdin through platform FFI |
| ~~[K4](#k4)~~ | ~~stdx extension funcTable failure across shared libraries~~ | **Retired** — original scenario passes on the pin on Linux x86_64 (#457) |
| [K5](#k5) | LTO produces bad GC stack maps | No LTO |
| [K6](#k6) | `-dead_strip` aborts at runtime | Do not enable it |
| [K7](#k7) | Tuple/struct taken from `ArrayList.remove` miscompiled | Read before removing |
| [K8](#k8) | Nested derived generic `Hashable` crashes cjc | Handwritten `AstPtr` equality/hash |
| [K9](#k9) | `Float64.parse` misrounds decimals | `fnum` parser and exact test oracle |
| [K10](#k10) | `cjpm test` progress reporter stalls | `--no-progress` |
| [K11](#k11) | Member-only build does not see workspace stdx | Declare stdx in each importing module |
| [K12](#k12) | `cjfmt` exits zero on syntax errors | No reliable failure check in generators yet |
| [K13](#k13) | macOS clears reachable objects' weak references | Check retention by identity |
| [K14](#k14) | CJMP at `-O2` leaks std bodies into product | `platform` uses `-O1` |
| [K15](#k15) | Tests cannot import/link a CJMP dependency's output | Copy product output; drop stale copies |
| [K16](#k16) | Non-product CJMP tests silently skipped | Keep limitation visible |
| [K17](#k17) | Concurrent child launches inherit other pipes | POSIX compiler shim |
| [K18](#k18) | cjpm drains stdout before stderr | No production workaround; distinct from K17 |
| [K19](#k19) | GC crash under ordinary test build | No confirmed fix |
| [K20](#k20) | Low-opt override dispatch broken after interface extend | No known affected cjls code |
| [K21](#k21) | Short strings have systematic hash collisions | Word index uses its own hash |
| [K22](#k22) | Optimized macro-host frame crashes GC | Avoid observed frame shape |
| [K23](#k23) | Loading std deriving after workspace macro aborts | Separate macro servers |
| [K24](#k24) | Two parameter marker macros crash compiler | No known affected cjls code |
| [K25](#k25) | `genericConstraint.toTokens()` throws | Iterate constraints |
| [K26](#k26) | Recursive generic-struct receiver faults under coverage | Recurse with ordinary kind/range arguments |
| [K27](#k27) | `cangjieLex` skips consecutive arrow recombination | Re-lex affected adjacent pairs in the test oracle |
| [K28](#k28) | Macro server reuses conflicting loaded package code | Known risk; no automatic restart on library switches |

## Evidence and use

<a id="k1"></a>
### K1

A spawn can remain on its spawner's run queue until a subsequent blocking foreign
call returns. Observed on `1.3.0-alpha.20261002`; OS/architecture of the standalone
probe are unrecorded in [PR #330](https://github.com/ide4cj/cjls/pull/330).
That PR records 17/1000 delayed spawns without a yield versus 0/1000 with one.
[`StdinStream.read`](../modules/platform/src/common/stdio.cj) calls
`sleep(Duration.Zero)` before blocking. [#324](https://github.com/ide4cj/cjls/issues/324)
has the server failure. The private probe archive mentioned by #332 is not a
repository artifact and is not a prerequisite for working here.

<a id="k2"></a>
### K2

cjc omits the C-to-native stub for foreign functions with LLVM-known libc names
(`read`, `write`, `open`, etc.), even without an explicit `@FastNative`. A blocking
call then prevents GC progress. [D13](adr/0013-stdin-is-read-with-readv.md) records
nightlies `20260918` and `20260925`, both `-O0` and `-O2`; OS is POSIX, exact host
unrecorded. Keep [C5](design/03-conventions.md): blocking foreign calls must switch
to native code. POSIX stdin uses [`readv`](../modules/platform/src/posix/stdio.cj);
Windows uses [`_read`](../modules/platform/src/windows/stdio.cj). Changing names
requires checking the generated call passes through `_CJ_MCC_C2NStub`.

<a id="k3"></a>
### K3

`std.env.getStdIn().read` reportedly returns only when the buffer fills or at EOF,
stalling an interactive protocol. Evidence: [#332](https://github.com/ide4cj/cjls/issues/332)
and the [`StdinStream` note](../modules/platform/src/common/stdio.cj), including the
reported one-byte-buffer stall. Exact nightly and observed OS/architecture are
unverified. Preserve descriptor-based stdin, subject to K1/K2; fake-transport unit
tests do not exercise the SDK's stdin implementation.

<a id="k4"></a>
### ~~K4~~ — Retired

**Status: retired.** The original scenario no longer reproduces on
`1.3.0-alpha.20261014001050`, Linux x86_64; the static-library restriction was
removed in [PR #457](https://github.com/ide4cj/cjls/pull/457).

Historical stdx extensions on user types lost funcTables across a shared-library
boundary: runtime SIGABRT, `F funcTable is nullptr`.
[#332](https://github.com/ide4cj/cjls/issues/332) records the defect;
[PR #457](https://github.com/ide4cj/cjls/pull/457) identifies the original scenario
as cjc `1.1.3` (original platform unrecorded) and verifies it no longer reproduces
on `1.3.0-alpha.20261014001050`, Linux x86_64. A separate intermediate library
exports generic `decode<T>` and `decodeArray<T>`; the executable round-trips
`Request` arrays through stdx serialization. All four static/dynamic combinations
of the intermediate library and stdx passed at both `-O0` and `-O2` (eight runs).
This does not establish a first fixed version or status on other platforms.

PR #457 retired the blanket static-library requirement and the corresponding
troubleshooting advice. The manifests still select static library output and
static stdx, but those settings are not evidence that K4 requires them.
[`cjls`](../modules/cjls/cjpm.toml) retains `--static` so the server runs without
an SDK environment. See [Development](development.md#toolchain-constraints) for
current linking constraints, including the dynamic system-library baseline.

<a id="k5"></a>
### K5

[D20](adr/0020-no-lto.md) records Linux x64 GC stack-map crashes on nightlies
`20260918` and `20260927`: 6/40 and 17/60 failures with LTO, versus 0/120 and 0/60
without it. Keep LTO out of manifests/CI. The existing re-enable criterion is
hundreds of successful `tests/e2e/test_idle.py` repetitions on a candidate nightly
with LTO; no such verification was performed here. Old local bitcode-link recipes
are not a supported release procedure.

<a id="k6"></a>
### K6

`-dead_strip` reportedly aborts at the first protocol message.
[#332](https://github.com/ide4cj/cjls/issues/332) is the public record; exact nightly,
OS/architecture and root cause are unverified. The linker-option name alone does
not establish which host was measured. Preserve the prohibition in
[Development](development.md#toolchain-constraints). This is separate from K5;
D20's LTO measurements do not establish evidence for dead stripping.

<a id="k7"></a>
### K7

At `-O2`, cjc miscompiles a tuple/struct destructured directly from
`ArrayList.remove(at:)`, including `list.remove(at: i)[1]`.
[#332](https://github.com/ide4cj/cjls/issues/332) and comments in
[`index_map`](../modules/index_map/src/index_map.cj),
[`body`](../modules/loupe/src/hir/body.cj),
[`infer`](../modules/loupe/src/hir/infer.cj) and
[`IdLruBench`](../modules/calca/src/id_lru_bench_test.cj) preserve the workaround:
read `list[i]` first, then remove it. Local historical notes report reproduction
through nightly `20261002`; exact host and original standalone output are
unverified. Do not simplify these sequences on the strength of a build passing.

<a id="k8"></a>
### K8

Nested derived `Hashable` on generic structs with a self-referential bound crashes
cjc in `CHIR::Type::StripAllRefs` at `-O2`.
[PR #30](https://github.com/ide4cj/cjls/pull/30) contains the minimal source and
nightlies `20260918`/`20260925`; its benchmark host was Darwin arm64, but the
reproducer's host is not explicitly identified. Local notes additionally report
`20261002` (not reverified). Keep handwritten equality/hash in
[`AstPtr`](../modules/ginkgo/src/ptr.cj). `-O0`/`-O1`, a non-generic outer, or
`K <: Hashable` alone reportedly avoid the crash; none is a reason to weaken its
actual bounds.

<a id="k9"></a>
### K9

`Float64.parse` reads some shortest decimals one ulp off.
[#332](https://github.com/ide4cj/cjls/issues/332),
[`RyuTest`](../modules/fnum/src/ryu_test.cj) and
[`parseFloat64`](../modules/fnum/src/parse.cj) record the limitation.
Local historical measurements: 458/100000 random values, Darwin arm64, `-O2`,
2026-09-27; exact nightly is unverified. Use `fnum.parseFloat64` (already used by
[`fjson`](../modules/fjson/src/reader.cj) and
[`ftoml`](../modules/ftoml/src/parser.cj)); Ryu's oracle uses exact `BigInt`
intervals. Old notes saying `FjReader` still delegates to std parsing are obsolete.

<a id="k10"></a>
### K10

The `cjpm test` progress reporter reportedly stalls and fails runs whose tests
passed. [#332](https://github.com/ide4cj/cjls/issues/332) is the defect record;
exact nightly/platform and root cause are unverified. Keep `--no-progress` in
[Development's test commands](development.md#focused-and-full-cangjie-tests) and
[CI](../.github/workflows/ci.yml). It does not prevent every SDK/compiler hang.

<a id="k11"></a>
### K11

`cjpm build -m <member>` reportedly ignores workspace-level stdx binary
dependencies. [#332](https://github.com/ide4cj/cjls/issues/332) is the public seed;
local historical notes report cjc/cjpm `1.3.0-alpha` in September 2026, exact nightly
and platform unverified.

The current workaround is to declare stdx binary dependencies in each module
that directly imports it, including test-only consumers (for example,
[loupe](../modules/loupe/cjpm.toml) and [fjson](../modules/fjson/cjpm.toml)). The
root workspace no longer declares stdx. This also lets external consumers resolve
these dependencies without inheriting the cjls workspace configuration. It does
not establish that the reported workspace-level SDK defect is fixed or impose a
blanket prohibition on member builds.

<a id="k12"></a>
### K12

`cjfmt` reportedly returns exit zero, copies input unchanged and prints `error:`
to stderr on syntax errors. [#332](https://github.com/ide4cj/cjls/issues/332) is the
public record. Local historical notes report `1.3.0-alpha`, 2026-09-27,
Linux/macOS/Windows; exact nightly/architectures unverified. Both
[`syntax_codegen`](../modules/syntax_codegen/src/generate.cj) and
[`fbs_codegen`](../modules/fbs_codegen/src/generate.cj) discard stderr and check
only exit status, so they do **not** implement detection of this failure. Build
and test consumers as [Development](development.md#generated-code) requires.
Formatter error handling is follow-up work, not a check added by this registry.

<a id="k13"></a>
### K13

[PR #316](https://github.com/ide4cj/cjls/pull/316) records reachable trees' weak
references clearing on macOS arm64, nightly `20261002`: 13/300 with a later-used
local and 55/300 with a parse memo, versus none in the Linux control.
[`ParseLruTest`](../modules/loupe/src/syntax/syntax_test.cj) checks retention with
identity and execution counts instead. Its remaining weak-reference leak checks
can pass spuriously on macOS; no Linux-only guard is implemented there.
The helper also waits after GC because clearing is asynchronous. Local notes
report std-only reproduction and rarer failures on `20261012`, not independently
verified here. A weak reference is not proof of retention, and macOS clearing is
not proof of deallocation.

<a id="k14"></a>
### K14

[D102](adr/0102-the-multiplatform-module-is-built-without-o2.md) records CJMP
common CHIR retaining imported std function bodies at `-O2`/`-Os`, followed by
duplicate definitions at link: Linux `20261002`, macOS `20260918` (architectures
unrecorded there). [#332's CJMP evidence](https://github.com/ide4cj/cjls/issues/332#issuecomment-6143375439)
identifies tools commit `3009d063`; different common/product optimization levels
are refused. Keep [`platform`](../modules/platform/cjpm.toml) at `-O1`, ordinary
modules' `-O2` in per-target release options, and no root `-O` (D51/D102).

<a id="k15"></a>
### K15

`cjpm test` cannot find a CJMP dependency under `src/<set>/product`, unlike build.
[#332's CJMP evidence](https://github.com/ide4cj/cjls/issues/332#issuecomment-6143375439)
records nightly `20261002`, tools `3009d063`; platform unverified.
[`platform/build.cj`](../modules/platform/build.cj) lifts `.a`/`.cjo` output after
building and removes those copies beforehand: stale copies shadow the new product
when building dependents. Preserve both stages. The script walks `target/` because
cjpm does not pass the target directory; arbitrary external target directories
are not covered by this workaround.

<a id="k16"></a>
### K16

[D101](adr/0101-platform-code-is-a-multiplatform-module.md) and
[#332's CJMP evidence](https://github.com/ide4cj/cjls/issues/332#issuecomment-6143375439)
record `*_test.cj` in non-product common/intermediate sets being neither compiled
nor run on `20261002`, tools `3009d063`; platform unverified. Only product-set
tests run. No workaround is implemented for shared-set tests; do not interpret
a passing `platform` suite as coverage of hypothetical tests in those sets.

<a id="k17"></a>
### K17

[#342](https://github.com/ide4cj/cjls/issues/342) records Linux x64 hangs on nightly
`20261002`: concurrent `cjc` children inherit each other's pipe write ends and
`cjpm` never sees EOF. Attribution to `std.process.launch` versus cjpm remains a
hypothesis. The [POSIX cjc shim](../.github/actions/setup-cangjie/shim/cjc) closes
inherited descriptors before executing the real compiler; [Development](development.md#select-the-pinned-sdk)
and the [pre-push hook](../.githooks/pre-push) put it first on PATH. This is the
observed production hang, distinct from K18.

<a id="k18"></a>
### K18

[#332's evidence](https://github.com/ide4cj/cjls/issues/332#issuecomment-6196755225) record a synthetic
Linux x64 reproduction, `1.3.0-alpha.20261014001050`, 2026-10-15: cjpm reads child
stdout to EOF before draining stderr, hanging when stderr fills its pipe.
A compiler wrapper writing 100000 stderr bytes hung; 1000 passed. Not seen in a
real dependency scan; no production workaround is implemented. K17's shim does
not make the two streams drain concurrently. The earlier attribution of #342's
55-minute hang to this defect was explicitly withdrawn in #332.

<a id="k19"></a>
### K19

[#332's evidence](https://github.com/ide4cj/cjls/issues/332#issuecomment-6209598955) record one Linux x64
`ubuntu-latest` GC-thread SIGSEGV in `BaseObject::GetSize`, nightly
`1.3.0-alpha.20261014001050`, during
[`NewFilePackageTest`](../modules/cjls/src/handlers/new_file_test.cj),
[run 38779367435](https://github.com/ide4cj/cjls/actions/runs/38779367435).
An unchanged rerun passed; it is not a fix. A stale root/bad stack map is a
hypothesis, not proof of K5 or K22.

[PR #477](https://github.com/ide4cj/cjls/pull/477) also records repeated macOS
arm64 GC stack-scanning SIGSEGVs on `1.3.0-alpha.20261014001050` in both macro-host
gates ([job](https://github.com/ide4cj/cjls/actions/runs/39778330777/job/119823116374)).
The reported runtime frames include `StackGrowStackInfo::RecordStackPtrs`; the
managed safepoint varies across `.cjo` lowering. These frames alone do not establish
that stack relocation caused the crash. An unchanged rerun passed before any stack
setting changed. A later run with `cjStackSize=8MB` also passed, but there was no
controlled comparison establishing an effect on the failure rate. The stack
override was withdrawn; CI uses the runtime defaults. Removing iterator
temporaries from the gate did not prevent the crashes and was also reverted.
No minimized reproduction, confirmed workaround, or common root cause with the
Linux observation is established.

<a id="k20"></a>
### K20

[#332's evidence](https://github.com/ide4cj/cjls/issues/332#issuecomment-6209825845) contain a one-file
reproduction on Linux x64, `1.3.0-alpha.20261014001050`, 2026-10-16: once an
`extend A <: I` adds an interface, calls through `A`/`I` ignore a subclass override
at `-O0`, `-O1` and `-g`; `-O2` dispatches correctly. No cjls code is known to hit
it and no workaround is adopted. Coverage and `platform` use affected optimization
levels; that alone does not prove a failing dispatch. Analysis keeps the language's
hierarchy semantics ([D128](adr/0128-a-members-hierarchy-is-matched-by-name-and-parameters.md)).

<a id="k21"></a>
### K21

[#332's evidence](https://github.com/ide4cj/cjls/issues/332#issuecomment-6210188181) record systematic
`String.hashCode` collisions on Linux x64, `1.3.0-alpha.20261014001050`, 2026-10-16:
`"ab"`/`"abc"` and 1256 of 47988 strings of 1–3 bytes share a hash with another.
Maps compare keys, so this is not a map correctness failure. Hash-only filtering
could admit extra files. [`file_words`](../modules/loupe/src/file_words.cj) already
uses its own `mixWord` (FxHash); no new workaround is needed. The reported wyhash
port explanation is source-based evidence in #332, not a verified fix here.

<a id="k22"></a>
### K22

Local historical notes on [PR #384](https://github.com/ide4cj/cjls/pull/384) report
an `-O2` macro-host iterator lambda followed by reference locals crashing GC on
Linux, nightly `20261014`: 8/8 scenario failures, versus 0/10 after a plain-loop
check and separating send work. Exact build timestamp and upstream root cause
are unverified; the PR body does not contain these measurements. Preserve the
current [`host.cj`](../modules/macro_host/src/host.cj) structure pending a minimized
reproducer. Do not turn this observation into a general ban on iterator lambdas.

<a id="k23"></a>
### K23

[D123](adr/0123-std-macros-run-in-the-macro-server.md) records SIGABRT when loading
std deriving after executing a workspace `@CalcaTracked` in the same process;
the isolated pair aborted every time, while loading the library first did not.
Exact nightly/platform are unverified. Preserve separate std/workspace instances
in [`MacroServers`](../modules/macro_host/src/host.cj). This is a loading-order
failure distinct from K4's historical shared-library funcTables and K22's GC crash.

<a id="k24"></a>
### K24

Local historical compiler notes report ICE (`std::out_of_range`,
`unordered_map::at`, exit 134) for two macros stacked on one primary-constructor
parameter, cjc `1.3.0-alpha`; exact nightly, platform and standalone evidence are
unverified. Stacking on enum constructors reportedly works. No known cjls failing
site or dedicated workaround exists; retain as an unverified risk when extending
[`Serde`](../modules/stdxx/src/deriving/decl_shape.cj), not a new macro API rule.

<a id="k25"></a>
### K25

Local historical notes report `genericConstraint.toTokens()` throwing
`IllegalArgumentException: Unsupported ArrayList<T> in function toTokens()` for
a declaration with `where`, cjc `1.3.0-alpha`; exact nightly/platform and original
reproduction are unverified. The current
[`stdxx` constraint helper](../modules/stdxx/src/deriving/decl_shape.cj) iterates
constraints and emits their upper bounds individually; the old note's
`modules/cjls/src/macros/utils.cj` path is obsolete. Keep constraint handling in
source; no public minimized reproduction or general SDK fix is asserted.

<a id="k26"></a>
### K26

[PR #477](https://github.com/ide4cj/cjls/pull/477) reproduced a worker-process
SIGSEGV on Linux x86_64 with `1.3.0-alpha.20261014001050`, both in
[CI coverage](https://github.com/ide4cj/cjls/actions/runs/39766821925/job/119784229016)
and locally with:

```bash
cjpm test --coverage -g --no-progress --timeout-each=2m --exclude-tags gate --target-dir target/cov '--filter=BodyDefinitionTest.aFieldInALambdaOfAMethod'
```

The fault reads `SyntaxNodePtr<K>.range` inside recursive `tryToNode` calls.
Running the test directly under a debugger, without the worker configuration,
passed; the execution context matters. The same search algorithm passes the
focused coverage check when its kind and range are ordinary arguments of a
frozen helper, rather than fields read through a recursive generic-struct
receiver. Keep the wrapper/helper split in [ptr.cj](../modules/ginkgo/src/ptr.cj).
No standalone SDK-only reproduction, upstream root cause, or general restriction
on generic recursion is established by this observation.

<a id="k27"></a>
### K27

`std.ast.cangjieLex(">=> >=> >>")` on `1.3.0-alpha.20261014001050` yields
`GT DOUBLE_ARROW GE GT RSHIFT`: it recombines only the first `>=>`.
Reproduced on Linux x86_64 after the randomized macro re-lexing test found it
in [Windows CI for #481](https://github.com/ide4cj/cjls/actions/runs/39814126314/job/119947979493).
macOS is unverified. The pinned runtime's
[`CJ_AST_Lex`](https://github.com/cangjie-bot/cangjie_runtime/blob/c1e289a7d43cb2e5a05add8b58ee7306dcfcdc3b/stdlib/libs/std/ast/native/ast_api.cpp)
consumes two tokens for `TryCombineDoubleArrow`, then unconditionally consumes
one more token before checking the next pair. The second pair's first token
therefore bypasses recombination. This is a `std.ast` wrapper defect, not a
platform-specific lexer rule.

The [macro re-lexing oracle](../modules/macro_server/src/macro_relex_test.cj)
re-lexes residual adjacent `GE`/`GT` and `RSHIFT_ASSIGN`/`GT` pairs in isolation
with the SDK. It checks line and column adjacency so separated operators are
unchanged, and leaves already recombined pairs intact (`>=>=>` must not combine
twice around its middle `>`). Other token values remain the SDK's. Deterministic
regressions include consecutive pairs, spaces, newlines and every run of `>`/`=`
up to ten characters; the randomized property remains enabled. Production code does not emulate the
wrapper's skipped iteration. This workaround does not establish a general SDK
fix or validate the compiler's entire macro pipeline.

<a id="k28"></a>
### K28

On Linux x86_64 with pinned `1.3.0-alpha.20261014001050`, one `LSPMacroServer`
process reuses the first library of a macro package when a later request supplies
a different `libPath` for the same `packageName`. This was reproduced on
2026-10-28 while implementing [#515](https://github.com/ide4cj/cjls/issues/515).
Two separately compiled `toy.ms` libraries export `Which`, one generating
`class First {}`, the other `class Second {}`. Requests selecting the first then
the second library both succeed but both generate `First`. Separate compiler
cache directories alone therefore do not isolate dependency selections.

The reuse also affects different macro package names with conflicting linked
helpers. Two macro packages `toy.First` and `toy.Second`, each linked against its
own static `leaf` library whose `which()` returns respectively 1 or 2, both use
the first helper's result in one server process. Direct macro package names and
paths cannot establish that their transitive libraries are compatible.

The per-library-switch restart workaround was removed for its process-startup
cost ([D156](adr/0156-reuse-workspace-macro-process.md),
[PR #563](https://github.com/ide4cj/cjls/pull/563)).
[`MacroLibrarySwitchBench`](../modules/macro_host/src/library_switch_bench_test.cj)
retains the comparison workloads; that PR records approximate measurements under
ambient load, not a quiet-machine performance claim. Workspace libraries now share
one process even when their paths differ. This accepts the risk of an expansion
using previously loaded code; it does not establish an SDK fix. The std server
remains independent (K23), and explicit restarts after library rebuilds remain.

[`SameNameMacroLibraryTest.explicitRestartLoadsEachSelectedLibrary`](../modules/macro_host/src/same_name_test.cj)
builds both libraries and their helpers with the SDK and alternates between them
for identical and distinct macro package names. Explicitly restarting before each
call yields `First, Second, First, Second`; omitting `restartWorkspace()` reproduces
`First, First, First, First` on the pin. The process-reuse test checks SDK process
IDs rather than requiring the SDK defect to persist. macOS, Windows and other SDK
versions remain unverified by this local probe.

<a id="k29"></a>
### K29

On Linux x86_64 with `1.3.0-alpha.20261014001050`, compiling the root `loupe`
package with `@DerivePython` on its analysis result types crashes cjc with
SIGSEGV when all bindings are enabled together. Each file's binding group and
each pair of groups compile separately at `-O0`. Placing `@DerivePython` below
`@Derive[Equatable]` makes the combined package compile at `-O0`; wrapping the
generated equality extensions crashes even without optimization. With that
annotation order fixed, `-O1` and `-O2` still crash the compiler. Increasing the
macro runtime heap to 2 GB did not resolve the unoptimized failure.

The `loupe` manifest selects `-O0` for that package alone. Its HIR, syntax,
database and other subpackages retain the normal release optimization. Python
bindings use the dependency's `DerivePython` directly. The independent interop
example with exported structs, enums and a recursive class compiles, so this
observation does not establish a general restriction or an SDK-only reproducer
of the optimizer failure. Other SDK versions and native platforms are unverified.

## Reconciliation and remaining work

This registry starts #332's document, not its probe implementation. None of
`tests/sdk-probes/`, `scripts/sdk_probes.py` or the planned probe-policy ADR is
introduced here. Independent cjpm probes, run/pack commands, hang guards and
version-bump automation stay in #332. No mandatory probe command exists yet.
Existing tests/reproductions linked above are evidence, not standalone SDK probes.
Adding `K#` references at workaround sites is also part of that integration;
current descriptive comments remain available until then.

The #455 C audit used repository source/manifests, ADRs, #332 and its comments,
linked PRs/issues, and only relevant local language/toolchain notes as leads.
Private memory is not required to build, verify or interpret this document.
Uncorroborated imported observations are explicitly identified above; their
measurements were not rerun. Human review should confirm their provenance before
using them to relax a constraint or file a report upstream.

The following dispositions prevent old local guidance becoming competing rules:

- Setup, per-shell SDK environment and worktrees belong to
  [Development](development.md). Retire Claude hook/guard-specific inline
  `LD_LIBRARY_PATH` recipes, hard-coded SDK paths and assumed local-nightly
  selection. A selected pin is not proof a particular machine has it installed.
- Retire historical LTO bitcode-link instructions as a supported procedure (K5),
  old CJMP ADR numbers in notes (current decisions are D101/D102), the obsolete
  claim that `FjReader` delegates to std parsing (K9), and claims that coverage
  must rewrite manifests to remove `-O2` (current release options: D51).
- Macro hygiene, initialization, enum name collisions and consumer verification
  stay in [Development](development.md#toolchain-constraints),
  [C8](design/03-conventions.md) and affected module notes. Language semantics
  already modeled in source and tests stay there; compiler behavior is not
  automatically an SDK defect. Migrated module notes are linked from the
  [module guide](README.md#module-notes).
- Private timing/layout/general optimization observations (`VArray` tables,
  `@Frozen`, closure allocation, pinning costs, GC plateaus) are not portable
  prescriptions. Existing source and benchmarks remain their evidence; no new
  performance guarantee or mandatory rewrite is introduced. Benchmark procedure
  belongs to [Development](development.md#fuzzing-and-performance).
- Unrelated projects, personal preferences, private GitHub permissions and
  machine automation policies are outside this SDK migration.

This audit preserves the K4 retirement already accepted in PR #457 and removes no
other workaround. Except for K4's scoped verification and K19/K26/K27/K28's subsequent observations,
exact-pin status remains unverified. Missing host/build metadata, upstream reports and independent probes
remain explicit limitations. The next SDK bump needs evidence before retiring an
entry; a passing ordinary build alone does not establish that a scheduling, GC or
optimizer defect is fixed.
