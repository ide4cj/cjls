package calca

import std.collection.*
import std.sync.*

const FIRST_REVISION: Int64 = 1

let nextIngredient = AtomicInt64(0)

/**
 * Reserves `count` consecutive ingredient indices, process-wide, so the one index of an ingredient
 * names it in every database. Called once per `@CalcaInput` type and `@CalcaTracked` function, from the
 * static the macro gives it; the order of those calls decides only which numbers they get.
 */
func reserveIngredients(count: Int64): Int64 {
    nextIngredient.fetchAdd(count)
}

/**
 * The part of a database one input field or one tracked function keeps: its values, and how to
 * tell whether one of them changed.
 */
interface Ingredient {
    /**
     * Whether the value at `id` may have changed after `revision`. For a tracked function that may
     * mean verifying its memo, or executing it again, on `db`.
     */
    func maybeChangedAfter(db: Database, id: Id, revision: Int64): Bool

    func describe(id: Id): String

    /**
     * Whether a value on a cycle can be replaced by a fallback: a tracked function's `cycle` option.
     */
    func hasFallback(): Bool {
        false
    }

    /**
     * Called as a write opens a new revision, while nothing reads: when an ingredient lets go of
     * what it no longer needs.
     */
    func newRevision(): Unit {}
}

class IngredientTable {
    IngredientTable(let entries: Array<?Ingredient>) {}
}

/**
 * What every handle of one database shares: the revision, the ingredients, and the gate a write
 * goes through.
 */
class Runtime {
    private let revision_ = AtomicInt64(FIRST_REVISION)

    /**
     * For every durability, the last revision in which an input of at least that durability changed.
     */
    private let lastChanged = Array<AtomicInt64>(DURABILITIES, {_ => AtomicInt64(FIRST_REVISION)})

    /**
     * Copied on write, so the lookup every query makes takes no lock.
     */
    private let table = AtomicReference<IngredientTable>(IngredientTable([]))
    private let tableLock = Mutex()

    /**
     * What a write holds throughout, so writes go one at a time and the root handle waits for one
     * to end; an operation that begins meanwhile is cancelled. Readers count themselves in and out
     * without it.
     */
    private let gate = Mutex()

    /**
     * What a write waits for the count under, held only while it looks at the count: the last
     * reader out takes it to wake the write, never waiting for the change the write makes after.
     */
    private let drainLock = Mutex()
    private let drained: Condition
    private let inFlight = AtomicInt64(0)
    private let writePending = AtomicBool(false)

    /**
     * Which handle waits for which, and for what, while one waits for a memo another computes: a
     * wait that would close a loop is a cycle across threads rather than a deadlock.
     */
    private let waitLock = Mutex()
    private let waitsFor = HashMap<Int64, (Int64, DatabaseKey)>()

    private let nextHandle = AtomicInt64(0)

    Runtime() {
        drainLock.lock()
        drained = drainLock.condition()
        drainLock.unlock()
    }

    prop revision: Int64 {
        get() {
            revision_.load()
        }
    }

    func lastChangedAt(durability: Durability): Int64 {
        lastChanged[durability.rank].load()
    }

    func ingredient<I>(index: Int64, create: () -> I): I where I <: Ingredient {
        let found = match (lookup(index)) {
            case Some(ingredient) => ingredient
            case None => synchronized(tableLock) {
                match (lookup(index)) {
                    case Some(ingredient) => ingredient
                    case None =>
                        let created = create()
                        register(index, created)
                        created
                }
            }
        }
        (found as I).getOrThrow {=> IllegalStateException("ingredient ${index} is ${found.describe(Id(0))}'s, of another type")}
    }

    func ingredientAt(index: Int64): Ingredient {
        lookup(index).getOrThrow {=> IllegalStateException("no ingredient ${index} in this database")}
    }

    private func lookup(index: Int64): ?Ingredient {
        table.load().entries.get(index) ?? None
    }

    private func register(index: Int64, ingredient: Ingredient): Unit {
        let entries = table.load().entries
        let grown = Array<?Ingredient>(max(entries.size, index + 1), {i => entries.get(i) ?? None})
        grown[index] = ingredient
        table.store(IngredientTable(grown))
    }

    /**
     * Begins an operation of a handle outside any query, which a write waits for.
     *
     * @throws Cancelled - if a write is pending, or the handle is pinned to a revision gone by
     */
    func beginRead(pinned: ?Int64): Unit {
        while (true) {
            // counted in before looking for a write: a write marks itself pending before it counts,
            // so one of the two sees the other
            inFlight.fetchAdd(1)
            if (!writePending.load()) {
                try {
                    unwindIfCancelled(pinned)
                } catch (e: Cancelled) {
                    endRead()
                    throw e
                }
                return
            }
            endRead()
            if (pinned.isSome()) {
                throw Cancelled()
            }
            // the root handle waits for the write to end, and reads the revision it opens
            synchronized(gate) {}
        }
    }

    func endRead(): Unit {
        if (inFlight.fetchSub(1) == 1 && writePending.load()) {
            // the write looks at the count under the same lock, so it cannot miss this
            synchronized(drainLock) {
                drained.notifyAll()
            }
        }
    }

    /**
     * Cancels the operations in flight, waits for them to end, and makes `change` in a new
     * revision, which it is given. Holds the gate throughout, so nothing begins until it is done;
     * the ingredients let go of what they no longer need then, with nothing reading them.
     */
    func write<T>(change: (Int64) -> T): T {
        synchronized(gate) {
            writePending.store(true)
            try {
                synchronized(drainLock) {
                    while (inFlight.load() > 0) {
                        drained.wait()
                    }
                }
                for (ingredient in table.load().entries) {
                    ingredient?.newRevision()
                }
                change(revision_.fetchAdd(1) + 1)
            } finally {
                writePending.store(false)
            }
        }
    }

    /**
     * Records that an input of `durability` changed in `revision`, which makes every memo that read
     * inputs of that durability or a lower one verify its dependencies again.
     */
    func changed(durability: Durability, revision: Int64): Unit {
        for (rank in 0..=durability.rank) {
            lastChanged[rank].store(revision)
        }
    }

    /**
     * A number for a new handle, distinct from every other one's in this database.
     */
    func newHandle(): Int64 {
        nextHandle.fetchAdd(1)
    }

    /**
     * Records that handle `waiter` waits for `key`, which handle `owner` computes, until
     * `stopWaiting` or until the owner lets go of it.
     *
     * @throws CycleException - if `owner` waits, through others or not, for `waiter`
     */
    func startWaiting(waiter: Int64, owner: Int64, key: DatabaseKey): Unit {
        synchronized(waitLock) {
            var current = owner
            while (true) {
                if (current == waiter) {
                    let described = ingredientAt(key.ingredient).describe(key.id)
                    throw CycleException("cycle: ${described} is computed by a handle waiting for this one", [described])
                }
                current = (waitsFor.get(current) ?? break)[0]
            }
            waitsFor.add(waiter, (owner, key))
        }
    }

    func stopWaiting(waiter: Int64): Unit {
        synchronized(waitLock) {
            waitsFor.remove(waiter)
        }
    }

    /**
     * Whoever waited for `key` waits for its owner no more: it is free, whether or not the waiter
     * has woken to see it.
     */
    func released(key: DatabaseKey): Unit {
        synchronized(waitLock) {
            if (waitsFor.isEmpty()) {
                return
            }
            let freed = ArrayList<Int64>()
            for ((waiter, (_, awaited)) in waitsFor where awaited == key) {
                freed.add(waiter)
            }
            for (waiter in freed) {
                waitsFor.remove(waiter)
            }
        }
    }

    /**
     * How many handles wait for another's memo: for tests, to know one got there.
     */
    func waiting(): Int64 {
        synchronized(waitLock) {
            waitsFor.size
        }
    }

    /**
     * @throws Cancelled - if a write is pending, or `pinned` is a revision gone by
     */
    func unwindIfCancelled(pinned: ?Int64): Unit {
        if (writePending.load()) {
            throw Cancelled()
        }
        if (let Some(revision) <- pinned) {
            if (revision != this.revision) {
                throw Cancelled()
            }
        }
    }
}
