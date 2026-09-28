# `calca` — incremental computation, the salsa way

The incremental computation engine, salsa's model in Cangjie, for the frontend to be built on. No project dependencies. Two packages: `calca`, the runtime, and `calca.macros`, the macros that are its API; a user imports both.

The API is salsa's, spelled in Cangjie; every macro is `Calca`-prefixed:

```cangjie
@CalcaInput
public struct SourceFile {
  public let path: String   // a getter only
  public var text: String   // a getter and a setter
}

@CalcaInterned
public struct Name {
  public let text: String   // fields are `let`: they are the identity
}

@CalcaTracked
public func lineCount(db: Db, file: SourceFile): Int64 { file.text(db).split("\n").size }

let file = SourceFile(db, "a.cj", "…")             // salsa: SourceFile::new(db, …)
file.text(db)
file.setText(db).to("…")                           // .withDurability(Durability.High).to(…)
Name(db, "x") == Name(db, "x")                     // one Id
```

- **A database** is the user's interface over `Database` (salsa's `trait Db: salsa::Database`) and a class implementing it with a `prop storage: Storage` — a prop, since a `let` cannot implement an interface's. A `Storage` is one *handle*, used from one thread at a time: `Storage()` makes a database and its root handle, which reads the current revision and is the only one that changes inputs; `storage.snapshot()` gives another thread a handle pinned to the revision current then (salsa's `db.clone()`), and the class wraps that in a `snapshot()` of its own type.
- **Writes wait for operations, not for handles** — IntelliJ's read actions rather than salsa's handle count, because Cangjie has no deterministic destruction: `~init` runs only once the GC collects, which without allocation pressure is never, and a snapshot escapes any lexical scope. Every operation outside a query (a tracked call, a field read, an input created, a value interned) goes through the gate in `Runtime`, counted in flight, released in `finally`; nested ones only check. A write cancels what is in flight (the next calca call there throws `Cancelled`), waits for the count to drop to zero, and opens a new revision holding the gate. A snapshot used after that is `Cancelled` too, so one answer never mixes revisions, and there is nothing to close: a forgotten snapshot holds up nothing. A write — setting an input, or creating one — from a snapshot or from inside a query is an `IllegalStateException`; creating one opens no revision, since nothing computed can have read it — except a singleton (`@CalcaInput[singleton]`, salsa's `input(singleton)`: at most one row, `Config.get(db)` / `tryGet(db)`), which a query may have looked for: `get` and `tryGet` record a read of the table, and creating the row is a write of its own. A long computation of one's own calls `db.unwindIfCancelled()`, or the write waits for it.
- **The engine** is salsa's red-green algorithm: a memo records what it read, is reused when nothing did change (checked cheaply by `Durability` first, then dependency by dependency, which may execute those), and a value computed again equal to the old one keeps its old `changedAt` (backdating), so what read it does not run again — hence `@CalcaTracked` results are `Equatable`, unless `@CalcaTracked[noEq]`. A function needing its own value is a cycle, including when it is only found while verifying (whoever verifies the key executes it instead, which finds it). `@CalcaTracked[cycle: f]` recovers, as old salsa's `recover`: when every query executing on the cycle has a fallback, each is marked, depends on the union of what they all read (minus themselves), unwinds at its next read (`CycleUnwind`) and takes its fallback; otherwise it is a `CycleException`, `participants` naming the queries. A cycle across handles (D29) is a `CycleException` for the handle closing it, fallbacks or not.
- **Interned values** are collected once unused (D18). The table is a `Slab` of the fields, as a generated `CalcaFields_<Name>` struct (a tuple cannot be `Hashable`), with a `HashMap` from fields to `Id`; an `Id` is a slot's index and its generation, 32 bits each, so a collected value's `Id` never finds the one reusing its slot, and reading it throws. Interning records a dependency, `changedAt` now, with the interning query's own durability so far; reading records none. Only values interned by `Low` queries go (outside a query they are `High`), once unused for `revisions: N` active revisions of their table (3 by default; `@CalcaInterned[forever]` keeps them, and records nothing), collected in `newRevision` under the write gate. A tracked function of several arguments is keyed by them as one generated `CalcaFields_<function>` (of one, by the argument itself; of none, by `Unit`). A tracked function's keys are a `Slab` too; keyed by an interned type (the generated struct implements `InternedValue`, found out from the first key at run time), it drops the memos of collected values.
- **Generated code** keeps one process-wide descriptor per input type, interned type and tracked function in a static (`InputIngredient`, `InternedIngredient`, `TrackedFunction`), holding an ingredient index reserved at initialization; each database creates the matching per-database state lazily at that index. The body of a tracked function goes to `fetch` with every call, never into the static — see the static-initialization rule under macro mechanics.
- **One computation per memo** (D29): the handle verifying or computing a memo claims its key; another one waits for the claim, then takes what the owner left. A memo verified in the current revision is read without a claim. A waiter looks every 10 ms whether it was asked to stop; `Runtime.waitsFor` turns a wait that would close a loop across handles into a `CycleException`.
- **LRU** (D17): `@CalcaTracked[lru: N]` keeps the values of the `N` keys fetched last, their order an `IdLru`: a linked list over the keys' dense `Id`s, nothing hashed, so a touch adds ~1% to a fetch that hits (`LruFetchBench`). Eviction runs only as a write opens a revision (`Ingredient.newRevision`, under the gate), so no reader sees a value go; an evicted memo keeps its revisions and dependencies, is verified by its edges without executing, and is computed again only when fetched. After its inputs changed it cannot backdate: there is no old value to compare with.
- **Not there yet:** tracked structs, accumulators, tracked methods, dropping memo keys that are not interned values (#14).
