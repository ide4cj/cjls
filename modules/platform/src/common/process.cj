@NonProduct
features {}
package platform

import std.fs.Path
import std.io.{InputStream, OutputStream}

/**
 * A child started by `startPiped`.
 */
public interface PipedChild {
    /** What the child writes on its end of the pipe. */
    prop fromChild: InputStream

    /** What the child reads on its end of the pipe. */
    prop toChild: OutputStream

    /** Waits until it has exited, and lets go of what it held. */
    func wait(): Unit

    /** Ends it at once. */
    func kill(): Unit
}

/**
 * How a child started by `startPiped` finds its ends of the pipe, as text for its command line.
 */
public struct ChildPipes {
    public ChildPipes(
        /** What it reads: a file descriptor on POSIX, a handle on Windows. */
        public let read!: String,
        /** What it writes. */
        public let write!: String,
        /**
         * The process it is to watch and exit with, `None` where the platform ends it with this
         * process itself (a job on Windows).
         */
        public let parent!: ?Int64
    ) {}
}

/**
 * A child that could not be started.
 */
public class ProcessStartException <: Exception {
    public init(message: String) {
        super(message)
    }

    protected override func getClassName(): String {
        "ProcessStartException"
    }
}

/**
 * Starts `program` with the arguments `args` makes of its pipe ends, serial: a pipe each way that
 * is neither its stdin nor its stdout, those going nowhere and to this process's stderr, as its
 * stderr does; `libDir` first where the platform looks for its shared libraries. On POSIX through
 * `/bin/sh`, which moves the pipes to fds 3 and 4; on Windows by `CreateProcessW`, inheriting the
 * two pipe handles and stderr alone, suspended until it is in a job that ends it with this process
 * (D91).
 *
 * @throws ProcessException - if it cannot be started on POSIX
 * @throws ProcessStartException - if it cannot be started on Windows
 */
public common func startPiped(program: Path, libDir: Path, args: (ChildPipes) -> Array<String>): PipedChild
