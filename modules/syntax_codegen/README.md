# syntax_codegen

Generates syntax kinds and typed tree views from cjsyntax's kinds file and
ungrammar ([D10](../../docs/adr/0010-generated-syntax.md)). The input model and
accessor constraints are explained in [cjsyntax's notes](../cjsyntax/README.md#generated-tree-views).

The executable links `cjformat`, which depends on checked-in `cjsyntax` and
`ginkgo`. Build it before changing generated syntax (D147). If checked-in output
cannot build, restore it from git or repair it before rebuilding the generator;
the previously built generator can then generate the new kinds.

## Regenerate

Build from the workspace root, with the pinned SDK as described
in [Development](../../docs/development.md#select-the-pinned-sdk):

```bash
cjpm build
target/release/bin/syntax_codegen modules/cjsyntax/syntax_kinds.toml
```

Build before breaking or removing generated output. Edit
[`syntax_kinds.toml`](../cjsyntax/syntax_kinds.toml) and
[`cangjie.ungram`](../cjsyntax/cangjie.ungram), then regenerate
`cjsyntax/src/syntax_kind.cj` and `cjsyntax/src/ast/nodes.cj`. Review generator
notes about accessors requiring handwritten implementations in
[`node_ext.cj`](../cjsyntax/src/ast/node_ext.cj). Do not patch generated output.

Formatting uses the `cjformat` library in memory and rejects syntax errors before
writing a file. The built generator needs no SDK on PATH. Build/test consumers as
well: successful formatting establishes parsing, not type correctness.

## Verification

After regeneration, start with the relevant generator unit tests and these
checks from the workspace root:

```bash
cjpm test --no-progress --target-dir target/test '--filter=GeneratedFilesTest.*'
cjpm test --no-progress --target-dir target/test '--filter=ConformanceTest.*'
cjpm test --no-progress --target-dir target/test '--filter=RepositoryConformanceTest.*'
```

`GeneratedFilesTest` compares checked-in files with freshly generated, formatted
output. `ConformanceTest` exercises the checker and checks an external source
corpus only when `CJSYNTAX_CORPUS` is set to its directory.
`RepositoryConformanceTest` checks repository sources and has the `gate` tag,
so the coverage command excluding gates does not run it. Error-free trees must
match the ungrammar exactly. Erroneous trees may omit children and contain error
or misplaced-declaration nodes, but must preserve the allowed order and shape.
These checks validate tree/view agreement, not compiler acceptance.

Follow with [Development's grammar/generated-code checks](../../docs/development.md#choose-checks-for-a-change).
The generator tests import the generated consumer, exercising that dependency
and the library formatter also uses the checked-in syntax consumer.
