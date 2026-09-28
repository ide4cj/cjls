package calca

import std.collection.*
import std.sync.*

/**
 * An `@CalcaInput` type, process-wide: where its table and its columns are in any database. Held by the
 * static `@CalcaInput` generates; not for use by hand.
 */
public class InputIngredient {
    private let base: Int64

    /**
     * A `singleton` has at most one row per database, which `single` finds.
     */
    public InputIngredient(let name: String, let fields: Array<String>, let singleton!: Bool = false) {
        base = reserveIngredients(1 + fields.size)
    }

    /**
     * Adds a row, which `fill` gives a value in every column, in order. No revision begins: nothing
     * computed so far can have read the row. Except a singleton's, which a query may have looked
     * for: that one is added in a revision of its own.
     *
     * @throws IllegalStateException - if the handle is a snapshot, or is inside a query, or the
     * singleton is there already
     */
    public func create(db: Database, durability: Durability, fill: (InputRow) -> Unit): Id {
        let storage = db.storage
        storage.checkWritable("create")
        if (!singleton) {
            if (storage.batching.isSome()) {
                // the batch holds the gate
                return add(storage.runtime, durability, fill)
            }
            return storage.read {
                add(storage.runtime, durability, fill)
            }
        }
        storage.write {
            revision =>
            let id = add(storage.runtime, durability, fill)
            let table = table(storage.runtime)
            synchronized(table.lock) {
                table.createdAt = revision
            }
            // what looked for it read nothing of the row yet, so of no durability in particular
            storage.runtime.changed(Durability.High, revision)
            id
        }
    }

    private func add(runtime: Runtime, durability: Durability, fill: (InputRow) -> Unit): Id {
        let table = table(runtime)
        synchronized(table.lock) {
            if (singleton && table.rows > 0) {
                throw IllegalStateException("${name} is a singleton, and there is one already")
            }
            let id = Id(table.rows)
            fill(InputRow(this, runtime, id, durability))
            table.rows++
            id
        }
    }

    /**
     * The row of a singleton, `None` until it is created. Recorded as read by the query running,
     * which runs again once the row is created.
     */
    public func single(db: Database): ?Id {
        let storage = db.storage
        storage.read {
            let table = table(storage.runtime)
            let (created, createdAt) = synchronized(table.lock) {
                (table.rows > 0, table.createdAt)
            }
            storage.reportRead(DatabaseKey(base, Id(0)), Durability.High, createdAt)
            if (created) {
                Id(0)
            } else {
                None
            }
        }
    }

    /**
     * The value of `field` at `id`, recorded as read by the query running.
     */
    @Frozen
    public func get<T>(db: Database, field: Int64, id: Id): T {
        let storage = db.storage
        storage.read {
            column<T>(storage.runtime, field).get(storage, id)
        }
    }

    public func set<T>(db: Database, field: Int64, id: Id): Setter<T> {
        let storage = db.storage
        Setter(column<T>(storage.runtime, field), storage, id)
    }

    /**
     * `Name(id)`, what the input's `toString` gives.
     */
    public func describe(id: Id): String {
        "${name}(${id})"
    }

    @Frozen
    func table(runtime: Runtime): InputTable {
        runtime.ingredient(base) {=> InputTable(this)}
    }

    @Frozen
    func column<T>(runtime: Runtime, field: Int64): InputColumn<T> {
        let table = table(runtime)
        runtime.ingredient(base + 1 + field) {=> InputColumn<T>(table, base + 1 + field, fields[field])}
    }
}

/**
 * The row `InputIngredient.create` is adding.
 */
public class InputRow {
    InputRow(private let ingredient: InputIngredient, private let runtime: Runtime, private let id: Id,
        private let durability: Durability) {}

    public func put<T>(field: Int64, value: T): Unit {
        ingredient.column<T>(runtime, field).push(id, Stamp(value, runtime.revision, durability))
    }
}

/**
 * Changes one field of one input, in a revision of its own:
 *
 * ```cangjie
 * file.setText(db).to(text)
 * file.setText(db).withDurability(Durability.High).to(text)
 * ```
 */
public class Setter<T> {
    private var durability: ?Durability = None

    Setter(private let column: InputColumn<T>, private let storage: Storage, private let id: Id) {}

    /**
     * Keeps the field's durability unless given.
     */
    public func withDurability(durability: Durability): Setter<T> {
        this.durability = durability
        this
    }

    /**
     * Cancels what is in flight on the snapshots, waits for it to end, then sets the field in a new
     * revision, which leaves every snapshot taken before it cancelled. Returns the value it had.
     *
     * @throws IllegalStateException - if the handle is a snapshot, or is inside a query
     */
    public func to(value: T): T {
        storage.write {
            revision =>
            let old = column.replace(id, value, durability, revision)
            storage.runtime.changed(max(old.durability, durability ?? old.durability), revision)
            old.value
        }
    }
}

/**
 * The rows of one `@CalcaInput` type in one database. Its columns share its lock.
 */
class InputTable <: Ingredient {
    let lock = Mutex()
    var rows: Int64 = 0

    /**
     * The revision a singleton's row was created in; the first one until then.
     */
    var createdAt = FIRST_REVISION

    InputTable(let ingredient: InputIngredient) {}

    /**
     * Whether the singleton was created since: what looking for it records.
     */
    public func maybeChangedAfter(_: Database, _: Id, revision: Int64): Bool {
        synchronized(lock) {
            createdAt > revision
        }
    }

    public func describe(id: Id): String {
        ingredient.describe(id)
    }
}

class Stamp<T> {
    Stamp(let value: T, let changedAt: Int64, let durability: Durability) {}
}

/**
 * One field of an `@CalcaInput` type in one database.
 */
class InputColumn<T> <: Ingredient {
    private let stamps = ArrayList<Stamp<T>>()

    InputColumn(let table: InputTable, let index: Int64, let field: String) {}

    @Frozen
    func get(storage: Storage, id: Id): T {
        let stamp = synchronized(table.lock) {
            stamps[id.index]
        }
        storage.reportRead(DatabaseKey(index, id), stamp.durability, stamp.changedAt)
        stamp.value
    }

    /**
     * Called with the table's lock held, for the row being added.
     */
    func push(id: Id, stamp: Stamp<T>): Unit {
        if (id.index != stamps.size) {
            throw IllegalStateException("${table.ingredient.name}.${field} is given row ${id} where row ${stamps.size} is due")
        }
        stamps.add(stamp)
    }

    /**
     * Returns the stamp replaced.
     */
    func replace(id: Id, value: T, durability: ?Durability, revision: Int64): Stamp<T> {
        synchronized(table.lock) {
            let old = stamps[id.index]
            stamps[id.index] = Stamp(value, revision, durability ?? old.durability)
            old
        }
    }

    public func maybeChangedAfter(_: Database, id: Id, revision: Int64): Bool {
        synchronized(table.lock) {
            stamps[id.index].changedAt > revision
        }
    }

    public func describe(id: Id): String {
        "${table.describe(id)}.${field}"
    }
}
