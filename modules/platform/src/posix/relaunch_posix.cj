@NonProduct
features { user.platform.posix }
package platform

import std.env.getCommandLine

foreign func execvp(file: CString, argv: CPointer<CString>): Int32

/**
 * `execvp` with the process's own command line: the same program, found the way whoever started
 * it found it.
 *
 * @throws Exception - if `execvp` returns, which it does only when it failed
 */
public specific func relaunch(): Int64 {
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

public specific func tieChildrenToThisProcess(): Unit {}
