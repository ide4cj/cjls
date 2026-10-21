# lsp_codegen

Generates the checked-in [LSP types](../cjls/src/lsp_types/) from
[`metaModel.json`](metaModel.json) and the server's
[configuration](../cjls/lsp_codegen.toml). Change inputs and generator code rather
than generated files; the shared policy and verification are in
[Development](../../docs/development.md#generated-code).

## Regeneration

Run from the repository root with the SDK environment loaded (`cjfmt` is invoked
by the generator):

```bash
cjpm build
rm modules/cjls/src/lsp_types/*.cj
target/release/bin/lsp_codegen modules/lsp_codegen/metaModel.json -c modules/cjls/lsp_codegen.toml
```

Build first: deleting output temporarily prevents the workspace from building,
so `cjpm run` cannot bootstrap regeneration. The generator does not prune old
files. Review the output, run generator tests and build/test a consumer as
Development requires; formatter exit status alone does not prove valid output
([K12](../../docs/sdk-issues.md#k12)).

The config's `output-subpackage` combines with `[package].name` from its adjacent
`cjpm.toml`. `src-dir` comes from config, then manifest, then `src`; relative
paths resolve against the config directory. This follows cjpm's package naming
rule rather than treating the root package name as a directory. Configuration
edge cases are covered in [tests](src/config_test.cj).

## Type mapping

[Structure resolution](src/structures.cj) flattens extends, mixins and own fields
in that order, replacing redeclarations in place. Anonymous property structs are
named for the declaring owner, so inherited properties reuse the same type.
String-literal discriminator properties become struct tags. Anonymous literal
unions that cannot be named are rejected instead of silently merged. Generated
structs use named parameters and `@Serde[skipNone]`; serialization semantics live
in [stdxx](../stdxx/README.md#absent-and-null).

[Union resolution](src/types.cj) removes null into the nullable wrapper and emits
untagged enums. An alias supplies its union's name; subsequent equivalent aliases
reuse it. Otherwise names follow member order, with array members pluralized.
Variants with more required keys are tried first to prevent a smaller shape from
accepting a larger one. Tuple members become variants with multiple payloads.

Union variants are `As<Member>` because enum constructors enter package scope:
a bare `HoverOptions` variant would shadow the struct even with a qualified
payload type. Optional defaults are qualified when the field type exports its own
`None`. Preserve these names when changing generation; the general import and
macro constraints are in [Development](../../docs/development.md#toolchain-constraints).

[Enumerations](src/enumerations.cj) preserve forward compatibility: closed enums
have an `Unknown` payload, while open enums use transparent scalar structs. An
`extern` mapping adopts generated constants onto an external type through a
sealed interface and extension; a bare extension would not export them. Constants
already on the target belong in `declared` to avoid duplicate static names. This
keeps LSP error codes out of `jsonrpc`'s dependencies.

## Message specifications

[Message specs](src/messages.cj) carry method names, direction and parameter/result
types. Direction-specific interfaces let only inbound specs be routed and give
outbound calls their codecs. Params and results cross as `RawJson`; no-parameter
or null-result messages use `Unit`. The codecs live on specs because std's `Unit`
cannot be extended with `ToJson`, and generic routing should not need per-shape
overloads. Invalid inbound params become `INVALID_PARAMS`; invalid outbound
answers fail decoding with `FjException`.

Registrable specs use the model's `registrationMethod`, falling back to their
method, so related requests can share a registration. Partial-result and error-data
types are resolved but are not yet exposed on specs. See
[message tests](src/messages_test.cj) for the generated contract.

Generated doc comments escape block-comment delimiters: Cangjie comments nest,
so an unescaped glob can consume the rest of a file. The
[emitter tests](src/cj_emitter_test.cj) exercise that boundary.
