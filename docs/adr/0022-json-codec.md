# ADR-0022: The wire is read and written with fjson, through serde's derives

Status: accepted, 2026-09-27

## Context

- Every message went through two trees: bytes → `JsonValue` → `DataModel` → the type, and back. #9 measured the trees as most of the cost of a write (a `documentSymbol` answer of 550 symbols: 1.6 ms, 4 MiB) and of a keystroke's read; `fjson` (#32), a pull reader and a writer over bytes, was the fastest of five codecs on every message.
- A pull reader cannot rewind, so an untagged union cannot try its variants on the reader itself; and `params` may come before `method`, before anyone knows their type.
- `@DeriveExt[Serializable]` generated both directions from one name, configured by `@DeriveExtSerializable[...]`. serde splits them, `Serialize` and `Deserialize`, under one `#[serde(...)]`.
- The TOML configs of the generators are read by `cjtoml`, whose API is `Serializable`.

## Decision

- **Two interfaces in `fjson`**: `ToJson` (`toJson(w: FjWriter)`) and `FromJson<T>` (`static fromJson(r: FjReader): T`), implemented there for `String`, `Bool`, `Int32`, `Int64`, `UInt32`, `Float64`, `Array<T>`, `Option<T>`, and `HashMap<K, V>` with `K <: JsonKey<K>` (`String`). `Nullable`, `IntegerOrString`, `AnyValue` implement them in `stdxx`.
- **serde's derives**: `@DeriveExt[ToJson, FromJson]`, each on its own, and `Serializable` still for `DataModel`. One marker, `@Serde[...]`, configures all three; the declaration and its markers are read once into a model, so every derivation follows the same rules and a mistake is reported once.
- **serde's spelling** where serde has one: `rename` names a field *and* a variant; an enum with payloads says `untagged` or `tag: "kind"` (serde's default, externally tagged, is not supported, so there is none); `transparent`, `other`, `skipNone`. `value:` is left for what serde has no word for: an integer variant, and the value of a tagged struct.
- **What is not read stays bytes**: `RawJson`, serde_json's `RawValue`, a slice of the frame. `params`, a `result` and an error's `data` cross the `Handler` boundary as `?RawJson`; the route reads them as its types (`decodeParams`), and `encodeResult` writes a result into one.
- **An untagged union** reads the value's slice once per variant, in declaration order, until one reads to its end; **a tagged one** finds the tag in the slice, then reads the fields of the variant it names. Neither copies.
- **A struct** reads key by key into a local per field, skipping keys it does not know; a required field missing when the object closes is an `FjException` naming it. Keys it writes are encoded once, in globals (`FjName`).
- **One pass for the envelope**: `Body.fromJson` reads every key whatever their order. A failure that is not the protocol's own is `PARSE_ERROR` if the bytes are not JSON, `INVALID_REQUEST` otherwise — found by a second pass, on the error path only.
- **One reader for the read loop, one writer for writes** (under a lock), both kept from message to message; the writer is dropped after an answer of more than 1 MiB.
- `DataModel` stays for the TOML configs, and inside `AnyValue` (`LSPAny`), which carries any JSON as its tree.

## Consequences

- The server reads a client's bytes with a parser of our own before the JSON test suites and a fuzzer have been at it (Q20).
- A handler's params are read twice: skipped into their slice by the envelope, then read as their type. Reading them in place when `method` came first takes the route in the read loop (#31).
- An untagged union of several object variants reads the value once per variant it tries: `TextDocumentContentChangeEvent`, on every keystroke, reads it once or twice. Picking the variant by its required keys takes the generator knowing each struct's keys.
- `cjc` crashes (`CHIRType::FillGenericArgType`) compiling a package that uses `HashMap<String, V>` extended for itself; hence `JsonKey`.
