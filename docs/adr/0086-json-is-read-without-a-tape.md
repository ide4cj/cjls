# ADR-0086: JSON is read by the pull reader, not through a tape index

Status: accepted, 2026-10-11

## Context

- D22 reads the wire with `FjReader`, a pull reader over the frame's bytes, and a derived `FromJson` per type. A tape - a structural index of the bytes written in one pass, a token per value and key with its kind, its byte span and, for a container, the token after it (jsmn; simdjson's second stage) - was the alternative left untried: it skips a value and finds a key without a pass over the bytes, which is what an untagged union and `params` before `method` need.
- D71 gave the pull reader `mark()`/`rewind(mark)`, which serves both cases on the frame already in memory.
- The tape was built on branch `perf/tape-experiment` (commits `e70d0064`, `61429283`): `FjTape`, three parallel arrays, and `FjTapeB`, one `Int64` a token; a cursor with `FjReader`'s API plus `hasKey` and `seek`, strings with escapes unescaped by an `FjReader` rewound to them; `FjRpcBench`'s three messages decoded by hand over it, as a derived decoder would, and benched beside the same pull decoders in one binary (`FjTapeBench`, `FjTapeBBench`, `FjTapeAllocationBench`).

## Decision

- **No tape**: `FromJson` reads `FjReader`, and no second `fromJson` over an index is derived.

## Consequences

- On a quiet Linux x64 (`-O2`, medians ±1.5%, a second run within 3%), the tape loses on every message, in both layouts: a keystroke 0.73 µs pulled, 0.95 µs (layout A) and 0.89 µs (B) through the tape; a `documentSymbol` request 329 ns, 417 and 378 ns; a 64 KiB `didOpen` 108 µs, 182 and 185 µs, allocating 239 KiB where the pull reader does 153 KiB.
- Building the index alone costs 50-65% of the whole pull decode (391 ns of the keystroke's 0.73 µs, 71 µs of `didOpen`'s 108 µs): the pull reader's one pass is already the floor, and the tape adds a second over every string it reads.
- What the tape saves, the rewound reader of D71 already saves: a keystroke has an untagged union and still reads faster pulled.
- A tape could pay again where a message is read many times or out of order, which no LSP message is; the experiment's branch is kept to start from.
