# jsonrpc

A symmetric JSON-RPC peer with no knowledge of method names or LSP. Its
[manifest](cjpm.toml) records dependencies; [source](src/) defines the public API.

## Framing and dispatch

The [body codec](src/body.cj) distinguishes requests, notifications and responses
by the presence of `id`, `method`, `result` and `error`, in any key order. Most
payloads remain `RawJson` slices until the caller knows their type. If `method`
precedes `params`, `Handler.paramsReader` can decode params in place; the handler
also receives that value as `decodedParams`. Failed in-place decoding leaves the
raw bytes available for normal decoding (D73).

[`ErrorCode`](src/error.cj) is an open `Int32` newtype so unknown codes survive a
round trip. Only JSON-RPC codes belong here; the LSP generator adopts LSP codes
onto that type through its [extern mapping](../lsp_codegen/README.md#type-mapping).

[Transport interfaces](src/transport.cj) separate framed streams from the peer.
A `RpcException` means the frame was rejected while framing remains synchronized;
the read loop answers and continues. This includes oversized content whose known
length can be skipped. A `TransportException` means framing is lost and the loop
ends. Keep that distinction when adding failure paths.

## Threading and shutdown

[`Connection.serve`](src/connection.cj) calls the handler on the read loop,
sequentially in arrival order. The upper layer decides which work to spawn.
[`InboundRequest`](src/inbound_request.cj) carries the right to answer once;
`respondWith` converts failures into error responses. A handler that throws before
answering is answered by the connection. Sends are serialized under a mutex so
concurrent answers cannot interleave frames.

An outbound response is delivered by that same read loop to a capacity-one queue;
`PendingRequest.await()` blocks the caller's thread. Waiting in a handler callback
therefore deadlocks. The server's corresponding constraints are
[S10](../../docs/design/01-request-slice.md#s10-outbound-request-boundaries) and
[S13](../../docs/design/01-request-slice.md#s13-catch-failures-at-thread-boundaries):
every spawned boundary catches both `Exception` and `Error` internally.

Transports and connections implement `Resource`. Closing is idempotent and safe
from another thread, including while `serve` is blocked reading. It closes the
transport, cancels all in-flight inbound tokens and wakes outbound waiters with
an error. `serve` closes in `finally`, so EOF and lost framing settle outstanding
work too. Preserve this invariant in every shutdown path; see
[connection tests](src/connection_test.cj) for deterministic cases.
