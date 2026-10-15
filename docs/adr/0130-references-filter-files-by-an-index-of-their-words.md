# ADR-0130: References read only the files whose words, a tracked index of hashes per file, name the name

Status: proposed

## Context

- D124 searches references per request: the files of the scope whose text has one of the names (`mentions`, a substring over the rope's chunks), then `highlightRelated` in each. A public member's scope is every file of the project, so each request read every text again, and parsed and inferred each file the substring was in: `reserve` is in every file of std's sources, in "All rights reserved", and the request for `ArrayList.reserve` parsed all 495 (#388).
- Roslyn keeps a bloom filter per document (`SyntaxTreeIndex`, false positives 0.0001, persisted by checksum), IntelliJ an index of words to files (`IdIndex`); R1 and ty scan the text per request, as D124 did.
- Three questions were open: a set of names or a bloom filter; the lexer's tokens or a scan of the text; the cost of the first request, which makes every file's index, rather than one made ahead (D31's memory).

## Decision

- **An index of each file's words, a tracked function** (`fileWords`): a file's words, each a 64-bit hash, sorted and each once; asked by binary search. Made the first time a search asks for the file, made again only after the file's text changed; the scope's files filtered by it before any is parsed.
- **Hashes, not names nor a bloom filter.** std's sources have 194 distinct words per file on average (96 thousand in 495 files): 1.5 KB of hashes a file, 0.75 MB for std; a set of the names would hold each one's bytes and a `String` besides. A bloom filter at Roslyn's 0.0001 needs ~19 bits a word, a third of the hashes, and lets a file through one time in ten thousand; a 64-bit hash collides never in practice, and either only costs a parse. The third saved is not worth a filter to size.
- **A scan of the text, not the lexer's tokens**: a word is a run of what a name is made of, cut where the lexer cuts one (`isIdentLike`). A superset of the names the parser reads, a keyword taken as a name and a quote's `$name` included, with words of comments and strings besides: `size` is a word in code in 219 of std's files and anywhere in 237. The lexer would drop those 18 at 3.2 times the cost, 81.9 against 25.8 ms for std's 495 files (`FileWordsBench`, ±1%), and would have to keep a contextual keyword the parser makes a name.
- **Made on the first request, not ahead.** The first search pays for every file of its scope, 25.8 ms for std, next to seconds of parses and inferences for a common name; a search after it 62 µs, where #387's scan read 6 MB in 1.1 ms. Nothing is made for a workspace no one searches.

## Consequences

- A request after the first reads no text, only an edited file's again. `cjls-perf`'s `references` on std's sources, medians of quiet runs: `ArrayList.reserve` after `size` 3383 → 224 ms, after an edit 3473 → 164 ms; `size`, the first request, 6481 → 6441 ms, the index made in it.
- A file is let through only for a whole word: `fooBar`, `sizeOf` and `reserved` no longer have a file parsed for `foo`, `size` and `reserve`. Most of the time saved is this: a scan checking whole words, not built, would have saved it too, at no less than the substring scan's 1.1 ms a request on std's sources and no memory; the index makes up its 25.8 ms after about 25 searches, and its cost per request does not grow with the workspace's text.
- The queries executed by the first request grow by one per file of the scope: `tests/perf/thresholds.toml` holds them for std's sources, where #387's scan executed 512 for `ArrayList.reserve` and the index 46.
- `fileWords` is kept for every file a search read, as `fileSymbols` is for `workspace/symbol`: ~1.5 KB a file, under D31's budget for any workspace cjls opens.
