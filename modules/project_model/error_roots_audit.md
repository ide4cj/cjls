# Local error-root attribution

Audit for [#425](https://github.com/ide4cj/cjls/issues/425), on baseline
`25ced854e0ca7012eb28a31ea6b8b8fe7db1c131`, Linux x86_64, pinned
`cjc 1.3.0-alpha.20261014001050`. `ErrorRootsGateTest` passed unchanged
before inspection. The inventory at that revision was **69 local roots in 15 files**,
not the historical 82 in 18 files quoted when the issue was opened.
Every root below was inspected at its source and traced to its input.
The numeric baseline was unchanged by the attribution audit itself; later fixes
are recorded below.

The census counts HIR expressions with no directly unknown expression children.
A local use has no such children even when its declaration inherited an unknown
from an earlier expression. Consequently a `local` root is not necessarily an
independent cause. Optional-chain desugaring can also map several counted HIR
expressions to the same written name. Do not deduplicate those occurrences or
reinterpret the existing counts while updating their explanations.

## Inventory at the inspected revision

Paths below are relative to `modules/`; line numbers describe the baseline
revision above, not permanent identifiers. Multiplicity is shown with `×`.

| Source | Count | Inspected locations and cause |
|---|---:|---|
| `loupe/src/definition.cj` | 4 | 416: `param` and its optional name access; `skip(index)` is solved without the pipeline input (#246). |
| `loupe/src/hir/binary.cj` | 1 | 545: `it` in the second callback inherits the lost `Option.flatMap` result argument (#551). |
| `loupe/src/hir/body.cj` | 16 | 753, 756, 762, 764: `accessor`; 981×2: `param`; 1138, 1202, 1204, 1222: `one`; 1475, 1476×2: `param`/`one`; 1490, 1535, 1544: `one`. All originate in generic pipeline `filter`/`map` inputs (#246). |
| `loupe/src/hir/body_test.cj` | 11 | 130: filter's `i`; 135–136, 137×2, 138, 140–143, 155: `outer`, `inner`, `selector`, `arms`, `callee`. The latter ten inherit the unknown through `quests`, tuple destructuring and enum patterns (#246). |
| `loupe/src/hir/def_map.cj` | 2 | 28: `fileId`; 29: `file`; pipeline `filterMap`/`map` inputs (#246). |
| `loupe/src/hir/expansion.cj` | 4 | 490: `name`; 493–494: `last`, inherited from the map result; 609: fold's `b` (#246). |
| `loupe/src/hir/item_id.cj` | 2 | 333: map's `name` (#246); 334: the standalone pipeline lambda's `names` (#248), also downstream of the first failure. |
| `loupe/src/hir/item_tree.cj` | 5 | 212–213, 216–217, 219: map's `decl` and the `tree` pattern bound from it (#246). |
| `loupe/src/hir/macro_call.cj` | 1 | 163: map's `name` (#246). |
| `loupe/src/hir/scope.cj` | 14 | 457, 459: `fileId`/`file`; 462–463, 464×2, 465, 469, 473×3, 476×3: `names`, `name`, `ids`, `id`, `glob`, inherited through the pipeline result `levels` (#246). |
| `loupe/src/hir/server_macro.cj` | 1 | 550: map's `name` (#246). |
| `loupe/src/hir/signature.cj` | 2 | 267, 346: map's `one` (#246). |
| `loupe/src/hir/ty_relations.cj` | 4 | 248×2, 253×2: callback `i` loses the macro-member unknown cause (#552); see below. |
| `macro_host/src/host.cj` | 1 | 55: `one`, bound from the `library` match result after `Option.flatMap` (#551). |
| `rope/src/node.cj` | 1 | 44: fold's `child` (#246). |

The attribution is 62 roots to [#246](https://github.com/ide4cj/cjls/issues/246),
one standalone callback to [#248](https://github.com/ide4cj/cjls/issues/248),
two to [#551](https://github.com/ide4cj/cjls/issues/551), and four to
[#552](https://github.com/ide4cj/cjls/issues/552). No inspected root originates in
local generic functions (#241). Retain idiomatic production code: annotations
used in probes below are controls, not workarounds to insert into the repository.

## After joint generic-callee inference (#246)

With #246, the same Linux SDK census removes all **62 local roots** attributed
to generic pipeline callees. The current local baseline is **7 roots in 4 files**:
one standalone pipeline callback in `item_id.cj` (#248), the two `Option.flatMap`
roots in `binary.cj` and `macro_host/src/host.cj` (#551), and four callback roots
in `ty_relations.cj` (#552). The inspected inventory above remains historical.
The surviving `item_id.cj` row now names only #248.

The fix also removes six downstream nonlocal roots: `definition.cj`'s `??`,
the two indices in `body_test.cj`, and `expansion.cj`'s two indices and `??`.
The gate reported only these decreases; no new root or diagnostic was accepted.
The bounded, unbounded and collection-pipeline compiler-oracle scenarios exercise
both successful inference and rejection of incompatible consumers. Fixture checks
also reject any inference variable left in expression, local or pattern results.

## Compiler and inference controls

Small isolated sources were compiled with the pinned compiler using
`cjc --diagnostic-format noColor -Woff unused --output-type staticlib main.cj -o libaudit.a`.
A fresh server built at the baseline revision was initialized with that SDK,
waited for workspace load completion, then queried by hover after didOpen and
didChange. These observations are attribution evidence, not permanent expected
failures replacing focused tests for each eventual fix.

- `a |> map { i => i + 1 } |> collectArray`, for `a: Array<Int64>`, compiles
  but infers `Array<{unknown}>`; annotating the callback's `i: Int64` gives
  `Array<Int64>`. `(a |> skip(1) |> first) ?? return` likewise loses the element
  type. These are the nested generic-call constraint flow tracked by #246.
- `x.flatMap { it => Some(it) }`, for `x: ?String`, compiles but infers
  `Option<{unknown}>`, even though its callback parameter is already `String`.
  The conditional `if (it.isEmpty()) { None<String> } else { it }` and the
  explicitly wrapped `else { Some(it) }` also fail. Explicit `<String>`, an
  expected `?String` on the binding, or a separately typed
  `(String) -> ?String` callback all give `Option<String>`. This is #551,
  distinct from standalone-lambda inference and function-valued pipeline callees.
- Ordinary `(0..a.size).iterator().all { i => ... }` with `a: Array<Int64>`
  infers `i: Int64`, including recursive calls and an enclosing enum-pattern
  match. The four roots in `ty_relations.cj` are not a normal range inference gap.

For the last group, tracing the unexpanded census's HIR established:

```text
sub.kind(db), sup.kind(db)       TodoTy(MacroMember)
subs, sups, subParams, .size     TodoTy(MacroMember)
0..subs.size                    Range<TodoTy(MacroMember)>
.iterator()                     Iterator<TodoTy(MacroMember)>
.all                            ((TodoTy(MacroMember)) -> Bool) -> Bool
callback i and its two uses     ErrorTy
```

The census has no `@CalcaInterned` output for `Ty.kind`. The unavailable-input
cause survives through the receiver and its callback signature, but is then
lost in the lambda parameter. #552 tracks that A30 violation. Dropping the four
entries, or treating them as four independent source errors, would conceal the
problem. The same reasoning should be checked for `UnknownTy` when fixing it.

## Keeping the audit useful

`error_roots_known.txt` now stores the issue explanation on each `local` row.
The gate reads inline explanations, retains them when `UPDATE_EXPECT=1` changes
counts, removes them with disappeared groups, and leaves a new local group as
`?`. An ordinary gate run rejects an unexplained local group. New or removed
counts still fail in both directions; an update never substitutes for reviewing
the reported source positions and the issue's scope.

The focused `ErrorRootBaselineTest` exercises this preservation independently of
the corpus. Run the corpus gate with the normal development prerequisites:

```bash
cjpm test --no-progress --target-dir target/test '--filter=ErrorRootsGateTest.*'
```

When a group shrinks, inspect its remaining positions: one row may carry more
than one cause. Update the reason and the linked issue's completion evidence
alongside the count. #48 still requires fixing the remaining causes, and #550
explicitly includes the two discoveries rather than treating attribution as
permission to begin Cleanup.
