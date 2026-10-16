# ADR-0130: References read only the files whose words, a tracked bloom filter per file, name the name

Status: proposed

## Context

- D124 searches references per request: the files of the scope whose text has one of the names (`mentions`, a substring over the rope's chunks), then `highlightRelated` in each. A public member's scope is every file of the project, so each request read every text again, and parsed and inferred each file the substring was in: `reserve` is in every file of std's sources, in "All rights reserved", and the request for `ArrayList.reserve` parsed all 495 (#388).
- Roslyn keeps a bloom filter per document (`SyntaxTreeIndex`, false positives 0.0001, persisted by checksum), IntelliJ an index of words to files (`IdIndex`); R1 and ty scan the text per request, as D124 did.
- Three questions were open: a set of names or a bloom filter; the lexer's tokens or a scan of the text; the cost of the first request, which makes every file's index, rather than one made ahead (D31's memory).

## Decision

- **An index of each file's words, a tracked function** (`fileWords`): a file's words, each a 64-bit hash, in a blocked bloom filter. Made the first time a search asks for the file, made again only after the file's text changed; the scope's files filtered by it before any is parsed.
- **A bloom filter, not the hashes nor the names.** std's sources have 194 distinct words per file on average (96 thousand in 495 files). The hashes sorted are 1.5 KB a file, 795 KB for std, a set of the names more still. A bloom filter at Roslyn's 0.0001 is 19.17 bits a word, 13 of them set, all in one block of 512 bits the hash chooses (a cache line): 254 KB for std, a third. It lets a file through for a word it lacks 1.3 times in ten thousand on std's words, none missed, which costs a parse; the files found for `size` and `getRawArray` are the same 237 and 5. Measured against the sorted hashes on a quiet A/B of `FileWordsBench` (two commits): a rare name looked up in every file 60.5 → 52.8 µs, a common one 84.8 → 78.6 µs, but every file's filter built in 51.4 against 25.7 ms, its fill ~20 ns a bit where 1–2 are due (#417).
- **The words hashed by FxHash a byte at a time** (`mixWord`), as the chunks are scanned: a word across two chunks is not copied. `String.hashCode` is faster on a whole string, but would need a `String` of each word, and std's collides for strings shorter than 4 bytes (`"ab"` and `"abc"`, #332). The filter remixes the hash (splitmix64's finalizer) before choosing bits: FxHash's low bits depend on its input's low bits alone. FxHash in a module of its own is #418.
- **A scan of the text, not the lexer's tokens**: a word is a run of what a name is made of, cut where the lexer cuts one (`isIdentLike`). A superset of the names the parser reads, a keyword taken as a name and a quote's `$name` included, with words of comments and strings besides: `size` is a word in code in 219 of std's files and anywhere in 237. The lexer would drop those 18 at 3.2 times the cost, 81.9 against 25.8 ms for std's 495 files (`FileWordsBench`, ±1%), and would have to keep a contextual keyword the parser makes a name.
- **Made on the first request, not ahead.** The first search pays for every file of its scope, 51.4 ms for std (25.7 once #417 is done), next to seconds of parses and inferences for a common name; a search after it 53–79 µs, where #387's scan read 6 MB in 1.1 ms. Nothing is made for a workspace no one searches.

## Consequences

- A request after the first reads no text, only an edited file's again. `cjls-perf`'s `references` on std's sources, medians of quiet runs, with the sorted hashes the filter replaced: `ArrayList.reserve` after `size` 3383 → 224 ms, after an edit 3473 → 164 ms; `size`, the first request, 6481 → 6441 ms, the index made in it.
- A file is let through only for a whole word: `fooBar`, `sizeOf` and `reserved` no longer have a file parsed for `foo`, `size` and `reserve`. Most of the time saved is this: a scan checking whole words, not built, would have saved it too, at no less than the substring scan's 1.1 ms a request on std's sources and no memory; the index makes up its 51.4 ms after about 50 searches, and its cost per request does not grow with the workspace's text.
- The queries executed by the first request grow by one per file of the scope: `tests/perf/thresholds.toml` holds them for std's sources, where #387's scan executed 512 for `ArrayList.reserve` and the index 46.
- `fileWords` is kept for every file a search read, as `fileSymbols` is for `workspace/symbol`: ~0.5 KB a file, under D31's budget for any workspace cjls opens.
