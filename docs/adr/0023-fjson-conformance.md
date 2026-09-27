# ADR-0023: fjson is held to JSONTestSuite, and reads a lone surrogate as U+FFFD

Status: accepted, 2026-09-27

## Context

- `fjson` reads every byte a client sends (D22) before the JSON test suites and a fuzzer had been at it (#31).
- [JSONTestSuite](https://github.com/nst/JSONTestSuite) is 318 documents a parser must accept (`y_`), must refuse (`n_`) or may do either with (`i_`), and 22 edge cases whose reading is up to the parser (`test_transform`): ~360 KB, MIT.
- fjson accepted every `y_` and refused every `n_` from the first run. Two places were inconsistent: `skipValue` let a lone surrogate escape (`"\ud800"`) through, as RFC 8259 does, while `readString` refused it, so one message could be JSON and not be readable. And the depth cap counted values, not containers: 513 nested arrays were read, 513 arrays around a number were not.
- A JavaScript string may hold a lone surrogate, and `JSON.stringify` writes it as its escape; a Cangjie `String` is UTF-8 and cannot hold one. Refusing it makes the whole message unreadable: a `didChange` dropped, and the document out of sync for good.

## Decision

- **The suite is vendored**, as it is upstream, in `modules/fjson/testdata/JSONTestSuite` (`-text` in `.gitattributes`, so no checkout rewrites a byte), and runs in every `cjpm test`: it is small, needs no network, and a client's bytes are read by nothing else. `conformance_test.cj` holds fjson to it: `y_` read, `n_` refused with `FjException` — by `skipValue` and by a read through the pull API alike — the `i_` pinned one by one, `test_transform` read as pinned, what stdx's parser also reads read as it reads it, and what fjson reads written and read back the same.
- **Fuzzing is deterministic and part of the tests**: every truncation of the `y_` and `i_` documents, every byte of them dropped or replaced by 31 bytes that matter to the grammar, 100 000 nested containers, and random values written and read back; `jsonrpc`'s `BodyFuzzTest` does the same to whole messages. Reading ends in the value or in `FjException` (`RpcException` for the envelope): any other exception ends the read loop, and the connection.
- **A lone surrogate escape reads as U+FFFD**, as `TextEncoder` makes it: one UTF-16 unit for one, so the client's positions still hold. An escaped high surrogate followed by an escape that is not a low one is U+FFFD, and that escape is read on its own. A surrogate encoded in UTF-8 (`ED A0 80`) is not JSON's but UTF-8's, and is refused, as is any invalid UTF-8.
- **Limits**, the same for `skipValue`, `rawValue` and `AnyValue`: 512 containers deep, the 513th refused. An integer read as one is an `Int64` (`UInt32` for `uinteger`, `Int32` for `integer`), without a fraction or an exponent; a number past `Float64` is `±Inf` (written back as `null`), below it `0`. No BOM, no UTF-16: LSP is UTF-8. A repeated key is read twice, left to the decoder (a map keeps the last); keys are compared as bytes, never normalized.

## Consequences

- stdx's parser accepts hex numbers and raw control characters in strings, and refuses numbers past `Int64` it could read as a `Float64`; the differential compares only what both read.
- `readFloat64` stays one ulp off on ~0.5% of shortest decimals (Q20): a round trip is checked to one ulp.
- A decoder of a recursive type other than `AnyValue` has no depth cap of its own; no LSP type a client sends is one.
