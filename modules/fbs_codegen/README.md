# fbs_codegen

Generates Cangjie views and optional writers over [fbs](../fbs/README.md).
The [configuration type](src/config.cj) describes supported options; the
[schema parser](src/schema.cj) defines the accepted single-file FlatBuffers
subset. Includes, RPC services and explicit field IDs are rejected. Declaration
and constructor name collisions require a config rename.

With `write = true`, generated `<Name>Data` writers pack tables, structs and
unions, with `toBytes()` on the root. Optional table fields default to `None` or
the schema's scalar default. Writers emit even empty vectors, because cjc's
readers dereference them without null checks; scalar defaults are omitted.
Vectors of unions are rejected. See [writer generation](src/emit_writers.cj).

## Regeneration and verification

Run from the repository root with the [SDK environment](../../docs/development.md#select-the-pinned-sdk)
loaded for the build. Build the generator **before** changing or
removing generated output, so a broken consumer cannot prevent bootstrapping it:

```bash
cjpm build
target/release/bin/fbs_codegen modules/cjo/cjo_format.toml
target/release/bin/fbs_codegen modules/macro_server/macro_msg_format.toml
cjpm test --no-progress --target-dir target/test '--filter=GeneratedFilesTest.*'
```

Run only the relevant generation commands. Consumer-specific SDK update steps
are in [cjo](../cjo/README.md#updating-the-sdk-schema) and
[macro_server](../macro_server/README.md#updating-the-sdk-protocol).
`GeneratedFilesTest` compares freshly generated, formatted bytes with checked-in
output for each config in `CONFIGS`. A new generated consumer needs an entry
there. The shared `cjformat` library formats in memory and rejects syntax errors before
writing. Built generators require no SDK environment. Compile and test consumers
when generated code changes, following [Development](../../docs/development.md#generated-code).
