# ADR-0071: A union reads its value on the reader itself, rewound to the value's start between attempts

Status: accepted, 2026-10-09

## Context

- D22 took the pull reader as one that cannot rewind, and from that followed the way a union reads: `rawValue` skips the value into a slice of the input, a second `FjReader` is made over the slice, and each untagged variant (or the tag, then the fields) reads the slice from its start. The slice costs a pass over the value and the reader an allocation (a 256-byte scratch buffer each) per union value; `TextDocumentContentChangeEvent` is one on every keystroke.
- The whole frame is in memory before anything reads it (`Content-Length`, D22), so "cannot rewind" was a property of the API, not of the input: the reader's state at a value's start is its position.
- `JsonCodecBench.readKeystroke`, the server's own path (envelope, then `decodeParams`), measured 2.0 µs where one hand-written pass over the same bytes (`FjRpcBench`, #32) takes 0.75 µs.

## Decision

- **`FjReader.mark()` and `rewind(mark)`**: where the next value starts, and back to it, on the same reader. A mark is taken only where a value starts.
- **A union reads on the reader it was given**: an untagged one rewinds between attempts and returns the first variant that reads, with no check that the value was read to its end, since a decoder reads exactly one value; a tagged one finds the tag in a first pass, rewinds, and reads the fields of the variant it names; a variant without payload skips the object it was named by.
- **`rawValue` stays** for what is not read at all: `params`, a `result`, an error's `data` (`RawJson`, D22).

## Consequences

- An untagged value whose first variant reads costs one pass and no allocation; each variant that fails costs the part of the value it read before failing. The ordering rule holds: narrowest first.
- `JsonCodecBench` on a quiet Linux x64 (`-O2`, medians ±0.1%): the keystroke 2.01 → 1.69 µs, its `params` alone 1.27 → 0.93 µs, the envelope unchanged at 0.68 µs; `didOpen` and the 550-symbol answer, with no union, unchanged.
- A tagged value is still read twice, on one reader; reading its fields in the first pass would take the generator buffering every variant's fields.
- `params` are still read twice, by the envelope and by the route (#31).
