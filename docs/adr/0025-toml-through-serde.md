# ADR-0025: TOML is read and written by ftoml, through the same @Serde model

Status: accepted, 2026-09-27. Closes #43 (Q21), and #31's correctly rounded `readFloat64`; supersedes D22's `DataModel` for the configs.

## Context

- The generators' configs were the last `Serializable` users besides `AnyValue`, read by the vendored `cjtoml`, which fails toml-test (1.0: 15 valid files refused, 9 read wrong, 54 invalid accepted) and knows no TOML 1.1. The workspace loader (#12) will read a client's `cjpm.toml`.
- TOML cannot be pull-read in document order as `FjReader` reads JSON: a table's keys may be spread over the file (`[a]`, later `[a.b]`, dotted keys).
- TOML has no `null` and no top-level scalar, and has dates and times, which `std.time` lacks. `Float64.parse` misrounds ~0.5% of shortest decimals.

## Decision

- **`ftoml`, TOML 1.1.0 exactly**: bytes to a document (`FtDocument`), tables in insertion order, every value and key with its span; every rule checked while parsing; an error an `FtException` with the byte, line and column. Its own `LocalDate`, `LocalTime`, `LocalDateTime`, `OffsetDateTime`. toml-test v2.2.0 runs in `cjpm test`, as JSONTestSuite does for `fjson` (#31, D26); tables and arrays nest at most 512 deep.
- **`FtWriter` writes without a tree**: plain keys, then `[header]`s and `[[header]]`s; inline tables inside a value.
- **`fnum`**, shared by `fjson` and `ftoml`: Ryu, and `parseFloat64`, correctly rounded (Clinger, Eisel-Lemire, a big-integer fallback, as Go's `strconv`).
- **`@DeriveExt[ToToml, FromToml]` over the `@Serde` model** that `ToJson`/`FromJson` use, not serde's `Serializer`/`Deserializer`: the formats disagree on what is valid, and a derivation per format reports it at compile time — a `Nullable` is a diagnostic, and `None` is left out whatever `skipNone` says. `@DeriveExt` derives any interface: the declaration is read once into a `DeclShape`, a derivation is a row of `DERIVATIONS`, and a marker no requested derivation reads is a diagnostic.
- **Where a value goes is the value's `tomlShape`** (`Omitted`, `Inline`, `Table`, `TableArray`), not a static property of its type as #43 proposed: an empty array of tables is `x = []` among the plain keys, `None` is nothing, and an untagged enum's shape is its variant's.
- **`FromToml` reads the document**, so an untagged enum tries its variants on the value at no cost, and a missing key is placed at its table.
- `cjtoml`, the `Serializable` derivation, `stdxx`'s `DataModel` helpers and `stdx.serialization` go; `AnyValue` is a JSON tree of its own, `fjson`'s `JsonValue`, and `stdxx.serialization` goes with it. D21's note on `cjtoml`'s license no longer applies.

## Alternatives

- **serde's run-time model** (one `Serialize` over `Serializer` interfaces): pays at N formats; at two, one model with a derivation per format spells a type once too, and keeps every call direct.
- **cangjie_toml**: 207/208 on 1.0, but datetimes never validated, 1.0 only, `DataModel` only; fixing it is most of writing one.
- **Keeping `cjtoml` for the generators**: not once the server reads a client's TOML.

## Consequences

- `ftoml` reads faster than both, and writes faster than `cjtoml` (cangjie_toml does not write): `FtomlBench` beside it.
- A document is a tree: a `FromToml` reads it after the whole file is parsed, which a pull reader would not need; configs are small.
