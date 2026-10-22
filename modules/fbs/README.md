# fbs

Runtime for the FlatBuffers views and writers produced by
[fbs_codegen](../fbs_codegen/README.md). The lazy-reader decision and format
compatibility contract are in [D37](../../docs/adr/0037-cjo-files-are-read-by-generated-views.md).

Reads validate the bytes they touch rather than verifying the whole buffer up
front. A vector's declared extent is checked when the view is constructed;
malformed data can still fail later with `FbException`. A union occupies two
field IDs, its tag followed by its value. See [read.cj](src/read.cj).

The [builder](src/builder.cj) writes back to front: children before parents,
table fields between `startTable` and `endTable` with each field followed by
`slot(id)`, and vector elements in reverse order. Offsets measure distance from
the buffer's end so growth preserves them. Values must align from the buffer's
start, as the SDK macro server's verifier requires; each table has its own
vtable. Builder round-trip tests alone do not prove compatibility with cjc's
reader; the [macro-server tests](../macro_server/README.md#tokens-and-verification) exercise it.

The package is deliberately named `fbs`: `std.ast` depends on `flatbuffers`, and
loading both under that name conflicts in macro-server tests. Generated views
import `fbs.*` and use unqualified runtime names; [name validation](../fbs_codegen/src/emit.cj)
reserves `RUNTIME_TYPES` to prevent collisions.
