# stdxx

Shared sum types and serialization derives. [Runtime types](src/) use `fjson`;
[`stdxx.deriving`](src/deriving/) is a separate macro package. Dependencies live in
the [manifest](cjpm.toml), and interfaces and marker options in the source.

## Derivation model

`@DeriveExt` generates implementations of `ToJson`, `FromJson`, `ToToml` and
`FromToml`, independently, for primary-constructor fields or enum variants. It is
separate from std's `@Derive` because std's derivation registry is protected.
When combined, `@DeriveExt` goes outside `@Derive`: macros expand inside out, and
it must extend the declaration that std's derive emits.

One [`DeclShape`](src/deriving/decl_shape.cj) is read per declaration. The
[`Serde` marker](src/deriving/serde_marker.cj) configures the requested codecs
inside `@DeriveExt`; it expands away after passing its options to the outer macro.
The codecs share a [wire model](src/deriving/serde_model.cj), so invalid options,
duplicate wire names and duplicate variant values are diagnosed consistently.
Backquoted identifiers use their unquoted names by default.

Keep field options in the existing marker. Reports of a compiler ICE with stacked
parameter macros are recorded with their uncertainty in
[K24](../../docs/sdk-issues.md#k24). Constraint emission deliberately walks upper
bounds instead of calling `genericConstraint.toTokens()`; see
[K25](../../docs/sdk-issues.md#k25). Generated names, initialization order, consumer
imports and verification follow
[Development](../../docs/development.md#toolchain-constraints); macro-package
compilation alone does not check an expansion in a consumer. The JSON writer
[pre-encodes field names](src/deriving/serde_to_json.cj) as `FjName` globals whose
initializers reach no user code.

## Absent and null

A constructor initializer supplies a missing field's default. Without an
initializer, the field's type determines whether it may be absent. JSON ignores
unknown keys unless strict decoding is requested and writes known keys in
declaration order. Without initializers, these four shapes preserve the
protocol's independent optional and nullable axes:

| Shape | Type | Read | Write |
|---|---|---|---|
| Required | `T` | Missing key is an error | Always present |
| Optional | `?T` | Missing or `null` becomes `None` | `None` becomes `null`, or is omitted with `skipNone` |
| Nullable | `Nullable<T>` | JSON `null` becomes `Null`; missing key is an error | Always present; `Null` becomes `null` |
| Optional and nullable | `?Nullable<T>` | Missing becomes `None`; `null` becomes `Some(Null)` | `None` is omitted with `skipNone`; `Some(Null)` stays `null` |

Without `skipNone`, `None` also writes `null` in the last row. LSP wire types need
`@Serde[skipNone]` to distinguish absent keys from explicit `null` (see
[protocol isolation](../../docs/architecture.md#macros-and-protocol-isolation)).
Spell `Nullable` directly in derived fields: the model recognizes its source
name, so an import alias under `?` loses the distinction and reads explicit
`null` as `None`. [Nullable tests](src/nullable_test.cj) cover the runtime value.

TOML has no null. Its derives diagnose `Nullable` fields and payloads, omit `None`
regardless of `skipNone`, and order plain keys before tables and arrays of tables.
An untagged value's `tomlShape` determines where it is written.

## Defaults and strict fields

A primary-constructor field's initializer supplies its value when the key is
absent, in both JSON and TOML. No marker is needed. A function call in the
initializer acts as a default factory and runs only for an absent key.
The initializer expression must also be valid in the generated static decoder,
independently of other constructor parameters.

Present values are still type-checked; explicit JSON `null` keeps the field's
existing null semantics and never selects a default. Without an initializer,
required fields reject missing keys and optional fields use `None`. Defaults do
not change serialization. A transparent struct reads its sole field from the
value itself, so there is no missing key for an initializer to fill.

`@Serde[denyUnknownFields]` on an object struct/class or tagged enum rejects keys
outside its wire field names and discriminator. Unknown keys remain ignored
without the marker. Each tagged enum variant accepts only its own payload keys;
empty variants accept only the tag. Nested types retain their own policy. TOML
errors retain the offending value's source location. Strictness is not meaningful
for scalar/untagged enums or transparent structs and is diagnosed there.

```cangjie
@DeriveExt[FromJson, FromToml]
@Serde[denyUnknownFields]
struct Policy {
    Policy(@Serde[rename: "line_width"] let lineWidth!: Int64 = 100) {}
}
```

## Tags and unions

A tagged struct writes a constant discriminator first and verifies it wherever
it occurs on read. This prevents an untagged union from accepting an unrelated
struct with otherwise compatible fields. A transparent struct serializes only
its single required field; field options cannot apply because no field name
reaches the wire.

Scalar enums serialize as strings or integers, with an optional `other` payload
for unknown values of the same kind. Payload enums explicitly choose a tag or
`untagged`. Untagged decoding tries variants in declaration order, rewinding the
same reader between failures, including integer overflow (D71). Put narrower
variants first. Multiple payloads encode an array of exactly that length; this
also represents tuples, since Cangjie tuple types cannot be extended with codec
interfaces. Tagged payloads use named object fields with the same optional rules.

Enum constructors enter package scope unqualified. Generated code must disambiguate
option constructors when another enum exports `None`. `FjKind` and `JsonValue`
likewise prefix their variants to avoid collisions with common type names. See
[C8](../../docs/design/03-conventions.md#c8-lsp-imports-and-aliases) and the
[LSP generator](../lsp_codegen/README.md#type-mapping).
