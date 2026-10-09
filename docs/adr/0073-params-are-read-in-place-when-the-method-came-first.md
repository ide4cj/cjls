# ADR-0073: Params are read in place, on the read loop, by the route's reader when `method` came before them; a reader that fails leaves them bytes

Status: accepted, 2026-10-09

## Context

- D22 reads the envelope in one pass and leaves `params` as a slice of the frame (`RawJson`), since `params` may come before `method`; the route then reads the slice as its type. D22 named the cost: a handler's params are read twice, and reading them in place when `method` came first "takes the route in the read loop".
- `JsonCodecBench` on the server's own path, after D71: a keystroke's `didChange` 1.69 µs, of which the envelope's skip over `params` 0.35 µs and a reader made for the slice 0.12 µs and 530 bytes; the same bytes read in one pass, envelope and params together, 1.03 µs.
- Every known client writes `method` before `params` (vscode-languageclient, Neovim, Zed, lsp4j; `jsonrpc` itself does).
- `jsonrpc` knows zero method names (D3); only the `Handler` above it knows what a method's params are.

## Decision

- **`Handler.paramsReader(method)`**: the handler's reader of a method's params where they lie, `None` to leave them bytes (the default). `Body.read(r, paramsReader)` calls it at the `params` key when `method` has been read, with the reader on the value; what it returns comes back as the message's `decodedParams` (`InboundRequest.decodedParams`, a third argument of `onNotification`), an `Any` the layer above casts to its type. The params stay `RawJson` in the body as well, a slice from the reader's `mark` to where the reader ended.
- **A reader that throws leaves the params unread**: the reader is rewound to the mark and the value skipped as before, so the route reads the slice itself and fails the same way as today, with an id to answer to. A frame whose `params` come before `method`, or whose method has no route, reads as before.
- **The route's reader is its spec's `decodeParams(r: FjReader)`**, generated beside `decodeParams(params: ?RawJson)`; a spec without params skips the value. `Router` keeps one per method; `Server.paramsReader` answers from it. A route takes the decoded value when it is of its type (`decoded as P`), the slice otherwise.
- **Decoding moves onto the read loop** for every message, a `ReadOnlyContext` handler's included, which read theirs on their own thread before: the route is now in the read loop, as D22 foresaw. The lifecycle still decides on the method alone, after the read: a refused request's params were decoded for nothing.

## Consequences

- `JsonCodecBench` (Linux x64, `-O2`, medians of 10 runs of the base and 2 of this branch, spread under 0.5%): the keystroke through the envelope and the route 1.73 µs and 1.38 KiB before; 1.65 µs and 0.88 KiB when the params still come as a slice (the reader's scratch buffer no longer allocated up front); **1.16 µs and 0.59 KiB** read in place. One hand-written pass over the same bytes is 0.75 µs (#32): what is left is the derived decoder's own work, the strings and `Option` locals and the box of the params into `Any`.
- `JsonRpcReader.read(paramsReader)` is the read the connection calls; `read()` stays for a transport that reads no bytes of its own (the test fakes), whose default gives no decoded params.
- A `FjReader` is made for a value only where a slice is read later (`RawJson.read`), and allocates its scratch buffer at the first escape it meets rather than on construction.
- `Body.fromJson(r)` remains, as `read` with no readers: what `fromJsonBytes<Body>` and the tests use.
