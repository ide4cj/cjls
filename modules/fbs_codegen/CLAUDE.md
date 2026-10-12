# `fbs_codegen`

Generates Cangjie views of a flatbuffers schema, on the runtime `fbs`; what it is run on, how, and what its output must keep are in `modules/cjo/CLAUDE.md`. A config it generates for goes in `CONFIGS` of `generated_files_test.cj`.

With `write = true` it also generates a writer of each declaration but an enum (`emit_writers.cj`): `<Name>Data`, a table's fields as named parameters (`None` or the schema's default for what may be absent) and `pack(b: FbBuilder)`, the root's `toBytes()`. A vector is always written, empty too, a scalar only when it is not its default: cjc's readers check no field for null. A vector of unions is refused.
