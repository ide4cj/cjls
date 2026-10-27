@NonProduct
features {user.platform.posix}
package platform

import std.env.getProcessId
import std.fs.Path
import std.io.{InputStream, OutputStream}
import std.process.*

/**
 * The script a child starts through: its pipes on fds 3 and 4 (the pipes `std.process` gives as
 * stdin and stdout, the only descriptors it passes), what it prints to stderr, never onto a pipe;
 * the library directories, one list, set in the script itself, where macOS does not strip them.
 */
const POSIX_LAUNCH =
    ##"lib="$1"; shift; LD_LIBRARY_PATH="$lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" DYLD_LIBRARY_PATH="$lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" exec "$@" 3<&0 4>&1 0</dev/null 1>&2"##

class PosixChild <: PipedChild {
    PosixChild(let process: SubProcess) {}

    public prop fromChild: InputStream {
        get() {
            process.stdOutPipe
        }
    }

    public prop toChild: OutputStream {
        get() {
            process.stdInPipe
        }
    }

    public func wait(): Unit {
        process.wait()
        ()
    }

    public func kill(): Unit {
        process.terminate(force: true)
    }
}

public specific func startPiped(
    program: Path,
    libDirs: Array<Path>,
    args: (ChildPipes) -> Array<String>
): PipedChild {
    let pipes = ChildPipes(read: "3", write: "4", parent: getProcessId())
    let process =
        launch(
            "/bin/sh",
            ["-c", POSIX_LAUNCH, "sh", libraryPathOf(libDirs), program.toString()]
                .concat(args(pipes)),
            stdIn: ProcessRedirect.Pipe,
            stdOut: ProcessRedirect.Pipe,
            stdErr: ProcessRedirect.Inherit
        )
    PosixChild(process)
}
