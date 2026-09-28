package calca

/**
 * Thrown out of a query whose answer nobody needs any more: a write is waiting for it to end, or
 * its snapshot is of a revision gone by, and nothing it computes would be current; or whoever uses
 * the snapshot asked it to stop. Catch it where the handle is used, and drop the handle.
 */
public class Cancelled <: Exception {
    Cancelled() {
        super("the query was cancelled")
    }

    protected func getClassName(): String {
        "Cancelled"
    }
}

/**
 * Thrown when a tracked function ends up needing its own result, directly or through others, and
 * not every query on the cycle has a fallback (`@CalcaTracked[cycle: f]`).
 */
public class CycleException <: Exception {
    /**
     * The queries on the cycle, described as `name(id)`, from the one needed again on; for a cycle
     * across handles, the query this handle waited for.
     */
    public let participants: Array<String>

    CycleException(message: String, participants: Array<String>) {
        super(message)
        this.participants = participants
    }

    protected func getClassName(): String {
        "CycleException"
    }
}

/**
 * Unwinds a query on a cycle whose queries all have a fallback, to where it takes its own.
 */
class CycleUnwind <: Exception {
    CycleUnwind() {
        super("a query on a cycle unwinds to its fallback")
    }
}

/**
 * Unwinds to whoever verifies `key`, which a query executing meanwhile needed: a cycle, found by
 * executing the key rather than verifying it.
 */
class VerifyingCycle <: Exception {
    VerifyingCycle(let key: DatabaseKey) {
        super("a query being verified is needed again")
    }
}
