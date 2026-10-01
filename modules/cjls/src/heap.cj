package cjls

import std.env.{getCommandLine, getVariable, setVariable}
import stdx.log.Logger
@When[os == "Windows"]
import std.env.getCommand
@When[os == "Windows"]
import std.process.{launch, ProcessRedirect}

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

@When[os != "Windows"]
foreign func execvp(file: CString, argv: CPointer<CString>): Int32

/**
 * Starts the server over again with `HEAP_SIZE`, unless `cjHeapSize` is set already (by the user,
 * or by this very step before). On POSIX the process is replaced, keeping its id and its stdio, and
 * this returns only if that failed; on Windows the server runs as a child on the same stdio, and
 * this returns its exit code.
 *
 * @return the exit code of the child the server ran as, or `None` to run in this process
 */
func relaunchWithLargerHeap(logger: Logger): ?Int64 {
    if (getVariable(HEAP_SIZE_VARIABLE).isSome()) {
        return None
    }
    setVariable(HEAP_SIZE_VARIABLE, HEAP_SIZE)
    try {
        relaunch()
    } catch (e: Exception) {
        logger.warn("could not start over with a larger heap: running on the default one",
            [(HEAP_SIZE_VARIABLE, HEAP_SIZE), ("cause", e)])
        None
    }
}

/**
 * `execvp` with the process's own command line: the same program, found the way the editor found
 * it, under the environment just changed.
 *
 * @throws Exception - if `execvp` returns, which it does only when it failed
 */
@When[os != "Windows"]
func relaunch(): ?Int64 {
    let args = getCommandLine()
    unsafe {
        let argv = LibC.malloc<CString>(count: args.size + 1)
        for (i in 0..args.size) {
            argv.write(i, LibC.mallocCString(args[i]))
        }
        argv.write(args.size, CString(CPointer()))
        execvp(argv.read(), argv)
    }
    throw Exception("execvp failed")
}

/**
 * Windows replaces no process: the child shares stdin, stdout and stderr, and this waits for it.
 */
@When[os == "Windows"]
func relaunch(): ?Int64 {
    let child = launch(getCommand(), getCommandLine()[1..], stdIn: ProcessRedirect.Inherit,
        stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
    child.wait()
}
