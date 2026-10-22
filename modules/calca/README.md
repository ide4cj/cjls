# Incremental computation

`calca` supplies inputs, interned identities and tracked functions without knowing
about projects, syntax or LSP. The runtime has no project dependencies. Consumers
import `calca` and `calca.macros`; the public macro documentation and executable
examples live beside [the macros](src/macros/) and in [the tests](src/calca_test.cj).
For cjls-specific query contracts, use the [analysis rules](../../docs/design/02-analysis.md).

## Handles, writes and cancellation

A consumer implements `Database` with a `storage: Storage` property. Each storage
is a handle used by one thread at a time. The root reads the current revision and
alone can create or set inputs; snapshots share its runtime but pin a revision.
The wrapper example and API contract are in [storage.cj](src/storage.cj).

Writes cancel and drain active operations, rather than waiting for snapshot
objects to be destroyed. Cangjie's GC cannot provide deterministic release of
those objects: an idle snapshot must not delay a write. After a write, an old
snapshot throws `CancelledException`; it needs no explicit close. A caller can
also supply cancellation to a snapshot. Long computations between calca calls
must check `unwindIfCancelled`, or a pending write waits for them.

Every outer operation enters the runtime's read gate and releases it in `finally`;
nested operations check cancellation. In [runtime.cj](src/runtime.cj), a reader
increments the in-flight count before checking for a pending write; a writer
marks itself pending before inspecting that count. Preserve this ordering so one
observes the other. The last reader wakes a writer under the drain lock, without
waiting for the gate the writer holds. A snapshot encountering a pending write
cancels immediately; a root read can wait for the write to finish.

Creating or setting inputs from a snapshot or inside a query throws
`IllegalStateException`. Ordinary input creation opens no revision because no
query could have read that row. Singleton creation does: a query may already have
observed the singleton's absence. `Storage.batch` cancels and drains once for all
its changes, permits no reads and opens no revision if no input changed (D75).
New ordinary input rows in a batch are stamped with the preceding revision so a no-change batch
cannot leave a future stamp. A batch is not a rollback transaction: changes made
before an exception remain. See [input.cj](src/input.cj) and
[batch tests](src/batch_test.cj).

## Reuse, cycles and concurrent claims

A memo records dependencies and their change revisions. Verification first uses
durability to avoid work, then checks individual dependencies. Recomputing an
equal result preserves its old change revision (backdating), so its readers can
remain valid. The `noEq` option deliberately gives up that comparison.

One handle claims a memo while verifying or computing it; another waits and then
uses the owner's result (D29, D35). A memo already verified in this revision can
be read without a claim or table lock. Its table uses a concurrent map and atomic
memo references; an LRU hit still locks to record use. Dependency edges retain the
memo entry or intern slot they read. They answer directly when possible, and
otherwise consult the ingredient, whose table can establish that an entry is gone
(D84, D85). The implementation is in [function.cj](src/function.cj).

A recursive fetch is a cycle, even if found during verification: verification
switches to execution to expose it. Recovery requires a fallback on every query
executing on the cycle; otherwise `CycleException` names its participants. Each
recovered query depends on the union of the cycle's external reads. Across
handles, the wait graph detects a loop; a handle gives way, releases the claim
another needs, then fetches again after that owner computes the cycle. Waiters
periodically check cancellation. See [storage.cj](src/storage.cj) and the claim
and cycle tests below.

Cancellation and cycle recovery use exceptions to unwind. Catching a broad
`Exception` in a query cannot make its result valid: marked frames store nothing
and rethrow even if the body returns (D42). Follow
[A21](../../docs/design/02-analysis.md#a21-do-not-swallow-query-unwinds) when writing consumers.

## Identity and bounded retention

Interned fields identify one value in a database. The field map points into a
generational slab: an `Id` has a 32-bit slot and 32-bit generation, so a stale
identity cannot read a new occupant. Looking up a collected value throws.
Interning records a dependency at the current revision with the query's durability;
reading its fields records no additional dependency.

Only values interned by Low-durability queries are collected. Outside a query they
are High and retained. Collection runs under the write gate after enough unused
active revisions of that table (three by default). `forever` retains values and
records no interning dependency. See [interned.cj](src/interned.cj),
[id.cj](src/id.cj) and [slab.cj](src/slab.cj).

Memo keys use a slab too. When a key is or contains an interned value, its memo
table registers with the corresponding interned tables and drops affected keys
on collection (D18). Generated `InternedValue` and `InternedFields` implementations
expose those dependencies; token-only macros discover field values through the
runtime `calcaKeyOf` cast. Dropping keys unrelated to interned values remains
[#124](https://github.com/ide4cj/cjls/issues/124).

LRU limits retained values, not all memo metadata. An `IdLru` orders dense keys
under the table lock; eviction happens during fetch, even within one revision
(D17, D36). An evicted memo retains dependencies and revision information, so a
dependent can verify it without forcing computation. Fetching its value computes
it again. If its inputs changed while evicted, no old value remains to backdate
against. Revision maintenance also trims unfinished fetches. See
[function.cj](src/function.cj) and [id_lru.cj](src/id_lru.cj). Timing claims belong
with the benchmarks and their recorded environment, rather than in this contract.

## Macro expansion and initialization

Macros emit a process-wide descriptor for each input, interned type and tracked
function; each database lazily creates its own state at the reserved ingredient
index. A tracked body reaches `fetch` through a generated `TrackedBody` type's
static function, rather than a closure allocated on each call. Do not put the body
in the descriptor's static initializer: cjc then rejects mutually calling tracked
functions as using statics before initialization. The reason is documented on
[`TrackedFunction`](src/function.cj).

Several arguments form a generated fields struct, one is its own key and zero use
`Unit`. Type-based mangling distinguishes overloads; methods also include the
receiver type in their name. The encoding and hashable fields generation belong
to [the macro implementation](src/macros/utils.cj), not a separately maintained
catalogue of generated names.

Tracked methods require the outer `@CalcaTracked` on their `extend` as well as the
method marks. The inner macros communicate names and options to the outer one;
the latter emits holders outside the `extend`, which cannot hold variables or
types. A non-static method includes its receiver in the key; a static one does
not. See [tracked.cj](src/macros/tracked.cj). Test expansion changes through a
consumer, not merely by compiling the macro package.

Diagnostics are ordinary query results, not accumulators (D14). calca does not
provide tracked structs; consumers intern stable locations instead (D34, D45).

## Choosing checks

Use [Development](../../docs/development.md#focused-and-full-cangjie-tests) for
commands, SDK prerequisites and the required broader checks. These neighboring
cases exercise the contracts above:

| Change | Start with |
|---|---|
| Write gate, snapshots, batches | [CalcaTest](src/calca_test.cj), [BatchTest](src/batch_test.cj), [SingletonTest](src/singleton_test.cj) |
| Claims, recovery, unwinding | [ClaimTest](src/claim_test.cj), [CycleTest](src/cycle_test.cj), [SwallowTest](src/swallow_test.cj) |
| Collection and verification | [InternedGcTest](src/interned_gc_test.cj), [EdgeTest](src/edge_test.cj), [LruTest](src/lru_test.cj) |
| Generated keys and methods | [ArgumentsTest](src/arguments_test.cj), [OverloadTest](src/overload_test.cj), [MethodTest](src/method_test.cj) |

Preserve the optimized removal workaround in `IdLruBench`
([K7](../../docs/sdk-issues.md#k7)). A normal passing build does not retire it.
For measurements, use the [benchmark procedure](../../docs/procedures.md#benchmark-isolation)
and the neighboring `*_bench_test.cj` cases; this document establishes no new timings.
