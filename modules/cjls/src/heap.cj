package cjls

import std.env.{getVariable, setVariable}
import stdx.log.Logger
import platform.{ProcessStartException, relaunch, tieChildrenToThisProcess}

/**
 * The runtime reads the heap's limit from this variable, once, before `main`.
 */
const HEAP_SIZE_VARIABLE = "cjHeapSize"

/**
 * The heap the server asks for when nobody chose one: the runtime's own 256 MiB does not hold a
 * large workspace, and an editor starts the server without the variable. A limit takes no memory
 * until it is used; one over the machine's memory is refused by the runtime, which then keeps its
 * default and says so on stderr.
 */
const HEAP_SIZE = "2GB"

/**
 * Starts the server over again with `HEAP_SIZE`, unless `cjHeapSize` is set already (by the user,
 * or by this very step before). On POSIX the process is replaced, keeping its id and its stdio, and
 * this returns only if that failed; on Windows the server runs as a child on the same stdio, tied to
 * this process (D78), and this returns its exit code.
 *
 * @return the exit code of the child the server ran as, or `None` to run in this process
 */
func relaunchWithLargerHeap(logger: Logger): ?Int64 {
    if (getVariable(HEAP_SIZE_VARIABLE).isSome()) {
        return None
    }
    setVariable(HEAP_SIZE_VARIABLE, HEAP_SIZE)
    try {
        tieChildrenToThisProcess()
    } catch (e: ProcessStartException) {
        logger.warn("the server's child will not die with this process", [("cause", e)])
    }
    try {
        Some(relaunch())
    } catch (e: Exception) {
        logger
            .warn(
                "could not start over with a larger heap: running on the default one",
                [(HEAP_SIZE_VARIABLE, HEAP_SIZE), ("cause", e)]
            )
        None
    }
}
