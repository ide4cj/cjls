package calca

import std.collection.*
import std.sync.*

/**
 * How long a handle waiting for another's memo goes before it looks whether it was asked to stop.
 */
let CLAIM_WAIT = Duration.millisecond * 10

/**
 * A `@CalcaTracked` function, process-wide: where its memos are in any database. Held by the static
 * `@CalcaTracked` generates; not for use by hand.
 *
 * The body comes with every `fetch` rather than here: a static whose initializer reaches the body
 * does not compile once tracked functions call each other, since cjc then sees the static used
 * before it is initialized.
 *
 * `equal` tells whether a value computed again is the one remembered, in which case the memo keeps
 * the revision it last changed in and what read it need not run again ("backdating").
 *
 * `lru` keeps the values of only that many keys, the ones last fetched, from one revision to the
 * next; the others lose their value but keep what they read, and are computed again when fetched.
 * `None` keeps every value.
 */
public class TrackedFunction<D, K, V> where D <: Database, K <: Hashable & Equatable<K> {
    let index: Int64

    public TrackedFunction(let name: String, let equal: (V, V) -> Bool, let lru!: ?Int64 = None) {
        index = reserveIngredients(1)
    }

    /**
     * The value of the function at `key`: remembered, if nothing it read has changed since, else
     * computed again. Recorded as read by the query running.
     *
     * @throws Cancelled - if a write is pending, or `db` is a snapshot of a revision gone by
     * @throws CycleException - if the value is already being computed on this handle
     */
    @Frozen
    public func fetch(db: D, key: K, execute: (D, K) -> V, recover!: ?(D, K) -> V = None): V {
        let storage = db.storage
        storage.read {
            let memos = storage.runtime.ingredient(index) {=> MemoTable(this, execute, recover)}
            let (value, memo, id) = memos.fetchValue(db, storage, key)
            storage.reportRead(DatabaseKey(index, id), memo.durability, memo.changedAt)
            value
        }
    }
}

/**
 * A value computed, with what it was computed from. An evicted memo has lost its value, but still
 * knows what it read and when it last changed, so it can be verified without computing it again.
 */
class Memo<V> {
    /**
     * The last revision this value is known to be current in.
     */
    let verifiedAt: AtomicInt64

    Memo(
        verifiedAt: Int64,
        let value: ?V,
        let changedAt: Int64,
        let durability: Durability,
        let dependencies: Array<DatabaseKey>
    ) {
        this.verifiedAt = AtomicInt64(verifiedAt)
    }

    /**
     * This memo without its value.
     */
    func evicted(): Memo<V> {
        Memo<V>(verifiedAt.load(), None, changedAt, durability, dependencies)
    }
}

/**
 * The key of a memo table and the memo at it, `None` until it is first computed.
 */
class MemoEntry<K, V> {
    MemoEntry(let key: K, var memo: ?Memo<V>) {}
}

/**
 * The memos of one tracked function in one database, one per key it was called with. A key's `Id`
 * is its slot in a `Slab`, given the first time it is seen, so what depends on it can name it.
 *
 * Keyed by an `@CalcaInterned` type, the table drops the memo of a value once the value is
 * collected, and its slot is reused under the next generation: a memo that read the dropped one
 * finds its `Id` stale, and counts it as changed.
 *
 * One handle at a time verifies or computes a memo: it claims the key, and another handle needing
 * it waits for the claim to go, then takes what the owner left, verified or computed. A memo already
 * verified in the current revision is read without a claim.
 */
class MemoTable<D, K, V> <: Ingredient & KeyedByInterned where D <: Database, K <: Hashable & Equatable<K> {
    private let lock = Mutex()
    let entries = Slab<MemoEntry<K, V>>()
    private let ids = HashMap<K, Id>()

    /**
     * The handle verifying or computing the memo at each key claimed.
     */
    private let claims = HashMap<Id, Int64>()

    /**
     * Notified as a claim goes.
     */
    private let released: Condition

    /**
     * When the keys are interned values, the key's `Id` for the `Id` of the value it is. `None` when
     * they are not; unknown until the first key.
     */
    private var byInterned: ?(?HashMap<Id, Id>) = None

    /**
     * When the function keeps only some values, the keys whose memo may hold one, in the order they
     * were last fetched. Touched under `lock`; trimmed in `newRevision`, while nothing reads.
     */
    private let used: ?IdLru

    /**
     * The function itself, the same whichever `fetch` gave it.
     */
    MemoTable(let function: TrackedFunction<D, K, V>, let body: (D, K) -> V, let recover: ?(D, K) -> V) {
        used = function.lru.map {capacity => IdLru(capacity)}
        lock.lock()
        released = lock.condition()
        lock.unlock()
    }

    /**
     * The `Id` of `key`, a new one the first time it is seen. Called with the lock held.
     */
    @Frozen
    private func internLocked(runtime: Runtime, key: K): Id {
        match (ids.get(key)) {
            case Some(id) => id
            case None =>
                let id = entries.insert(MemoEntry<K, V>(key, None))
                ids.add(key, id)
                if (let Some(map) <- internedKeys(runtime, key)) {
                    map.add((key as InternedValue).getOrThrow().calcaKey().id, id)
                }
                id
        }
    }

    /**
     * Where the key's `Id` goes by the value's, if the keys are interned values. The first key
     * decides, and registers the table with theirs, to be told what is collected: a macro sees only
     * tokens, so which type a key is is found out here. Called with the lock held.
     */
    @Frozen
    private func internedKeys(runtime: Runtime, key: K): ?HashMap<Id, Id> {
        if (let Some(known) <- byInterned) {
            return known
        }
        let found: ?HashMap<Id, Id> = match (key as InternedValue) {
            case Some(value) =>
                let ingredient = value.calcaKey().ingredient
                let table = (runtime.ingredientAt(ingredient) as InternedKeys).getOrThrow {
                    => IllegalStateException("${function.name} is keyed by ${ingredient}, which interns nothing")
                }
                table.watch(this)
                HashMap<Id, Id>()
            case None => None
        }
        byInterned = found
        found
    }

    /**
     * Drops the memos keyed by the values `collected`, and their keys' `Id`s with them.
     */
    public func dropKeys(collected: Array<Id>): Unit {
        synchronized(lock) {
            let map = match (byInterned) {
                case Some(Some(map)) => map
                case _ => return
            }
            for (value in collected) {
                let id = map.remove(value) ?? continue
                if (let Some(entry) <- entries.remove(id)) {
                    ids.remove(entry.key)
                }
                used?.remove(Id(id.index))
            }
        }
    }

    /**
     * The value at `id` and the memo holding it: remembered if the memo is verified, else computed
     * again. A use of the key, as far as `lru` goes; its `Id`, a new one the first time.
     *
     * A hit is one turn of the lock, the key interned and its memo read together, and marks
     * nothing as being worked on: a memo verified in this revision is neither verified nor
     * computed on any handle.
     */
    @Frozen
    func fetchValue(db: D, storage: Storage, key: K): (V, Memo<V>, Id) {
        let (id, current) = synchronized(lock) {
            let id = internLocked(storage.runtime, key)
            used?.touch(id)
            (id, entry(id).memo)
        }
        if (let Some(memo) <- current) {
            if (let Some(value) <- memo.value) {
                if (memo.verifiedAt.load() == storage.runtime.revision) {
                    return (value, memo, id)
                }
            }
        }
        let (value, memo) = fetchCold(db, storage, id, key)
        (value, memo, id)
    }

    /**
     * `fetchValue` of a memo not verified in this revision, or without a value.
     */
    private func fetchCold(db: D, storage: Storage, id: Id, key: K): (V, Memo<V>) {
        let databaseKey = DatabaseKey(function.index, id)
        storage.enter(databaseKey)
        try {
            let old = synchronized(lock) {
                claim(storage, databaseKey)
                // the owner waited for may have left it verified or computed
                entry(id).memo
            }
            try {
                match (old) {
                    case Some(memo) => match (memo.value) {
                        case Some(value) where verify(db, storage.runtime, memo, databaseKey) => (value, memo)
                        case None where verify(db, storage.runtime, memo, databaseKey) =>
                            execute(db, storage, databaseKey, key, old, unchanged: true)
                        case _ => execute(db, storage, databaseKey, key, old, unchanged: false)
                    }
                    case None => execute(db, storage, databaseKey, key, old, unchanged: false)
                }
            } finally {
                release(storage, databaseKey)
            }
        } finally {
            storage.exit(databaseKey)
        }
    }

    /**
     * Makes `storage` the one handle verifying or computing the memo at `key`, once whoever does
     * now is done. Called with the lock held, which a wait lets go of.
     *
     * @throws CycleException - if the handle computing it waits, through others or not, for this one
     * @throws Cancelled - if a write is pending, or the waiting handle was asked to stop
     */
    private func claim(storage: Storage, key: DatabaseKey): Unit {
        while (let Some(owner) <- claims.get(key.id)) {
            storage.runtime.startWaiting(storage.handle, owner, key)
            try {
                // no one tells a waiter its own snapshot was asked to stop: it looks now and then
                released.wait(timeout: CLAIM_WAIT)
            } finally {
                storage.runtime.stopWaiting(storage.handle)
            }
            storage.unwindIfCancelled()
        }
        claims.add(key.id, storage.handle)
    }

    private func release(storage: Storage, key: DatabaseKey): Unit {
        synchronized(lock) {
            claims.remove(key.id)
            storage.runtime.released(key)
            released.notifyAll()
        }
    }

    /**
     * Whether `memo` is current, marking it so if it is. Cheap when no input it could have read
     * changed since it was last verified; otherwise asks each of its dependencies in turn, which
     * may verify or execute those. A memo needed again while its dependencies are asked is not
     * current: executing it finds the cycle, and recovers from it if it can.
     */
    private func verify(db: D, runtime: Runtime, memo: Memo<V>, key: DatabaseKey): Bool {
        let now = runtime.revision
        let verifiedAt = memo.verifiedAt.load()
        if (verifiedAt == now) {
            return true
        }
        let changed = try {
            runtime.lastChangedAt(memo.durability) > verifiedAt && memo.dependencies.iterator().any {
                dependency => runtime.ingredientAt(dependency.ingredient).maybeChangedAfter(db, dependency.id, verifiedAt)
            }
        } catch (e: VerifyingCycleException) {
            if (e.key != key) {
                throw e
            }
            true
        }
        if (changed) {
            return false
        }
        memo.verifiedAt.store(now)
        true
    }

    /**
     * Runs the body and remembers the value. The memo keeps the revision `old` last changed in when
     * the value is the one `old` held, or when `old` was evicted but is `unchanged`: verified, so
     * computed again from what it was computed from before.
     *
     * On a cycle whose queries all have a fallback, the value is the fallback, and the memo depends
     * on what the whole cycle read.
     */
    private func execute(db: D, storage: Storage, databaseKey: DatabaseKey, key: K, old: ?Memo<V>,
        unchanged!: Bool): (V, Memo<V>) {
        let frame = storage.push(databaseKey)
        let value = try {
            let computed = body(db, key)
            if (frame.inCycle) {
                fallback(db, key, frame)
            } else {
                computed
            }
        } catch (e: CycleUnwindException) {
            if (!frame.inCycle) {
                throw e
            }
            fallback(db, key, frame)
        } finally {
            storage.pop()
        }
        let changedAt = match (old) {
            case Some(memo) where frame.durability >= memo.durability && (unchanged || isEqual(memo.value, value)) =>
                memo.changedAt
            case _ => frame.changedAt
        }
        let memo = Memo(storage.runtime.revision, value, changedAt, frame.durability, frame.dependencies.toArray())
        synchronized(lock) {
            entry(databaseKey.id).memo = memo
            used?.touch(databaseKey.id)
        }
        (value, memo)
    }

    /**
     * The fallback of a query on a cycle; what it reads is recorded, and unwinds nothing.
     */
    private func fallback(db: D, key: K, frame: ActiveQuery): V {
        frame.unwinding = false
        let recovered = recover.getOrThrow {=> IllegalStateException("${function.name} has no fallback")}
        recovered(db, key)
    }

    public func hasFallback(): Bool {
        recover.isSome()
    }

    private func isEqual(old: ?V, new: V): Bool {
        match (old) {
            case Some(value) => (function.equal)(value, new)
            case None => false
        }
    }

    /**
     * Verifying the memo at `id` for another one's sake, which is not a use of it. A memo with a
     * value that is not current is computed again, so backdating can tell whether it changed. An
     * evicted one never is: if nothing it read changed, neither did it; else it may have, and
     * whoever fetches it computes it. A memo dropped with its key is changed.
     */
    public func maybeChangedAfter(db: Database, id: Id, revision: Int64): Bool {
        let typed = (db as D).getOrThrow {=> IllegalStateException("${function.name} is given a database of another type")}
        let storage = db.storage
        let databaseKey = DatabaseKey(function.index, id)
        storage.enter(databaseKey)
        try {
            let now = storage.runtime.revision
            let found: ?(K, ?Memo<V>, Bool) = synchronized(lock) {
                match (entries.get(id)) {
                    case Some(entry) => match (entry.memo) {
                        case Some(memo) where memo.verifiedAt.load() == now => Some((entry.key, entry.memo, false))
                        case _ =>
                            claim(storage, databaseKey)
                            // the owner waited for may have left it verified or computed
                            Some((entry.key, entry.memo, true))
                    }
                    case None => None
                }
            }
            let (key, old, claimed) = found ?? return true
            try {
                match (old) {
                    case Some(memo) where memo.value.isNone() => !verify(typed, storage.runtime, memo, databaseKey) ||
                        memo.changedAt > revision
                    case Some(memo) where verify(typed, storage.runtime, memo, databaseKey) => memo.changedAt > revision
                    case _ => execute(typed, storage, databaseKey, key, old, unchanged: false)[1].changedAt > revision
                }
            } finally {
                if (claimed) {
                    release(storage, databaseKey)
                }
            }
        } finally {
            storage.exit(databaseKey)
        }
    }

    /**
     * Evicts the values of the keys fetched least recently, beyond `lru`.
     */
    public func newRevision(): Unit {
        synchronized(lock) {
            used?.trim {
                id =>
                if (let Some((_, entry)) <- entries.getAt(id.index)) {
                    entry.memo = entry.memo?.evicted()
                }
            }
        }
    }

    public func describe(id: Id): String {
        "${function.name}(${id})"
    }

    /**
     * Called with the lock held.
     */
    @Frozen
    private func entry(id: Id): MemoEntry<K, V> {
        entries.get(id).getOrThrow {=> IllegalStateException("${function.name} has no key ${id}")}
    }
}
