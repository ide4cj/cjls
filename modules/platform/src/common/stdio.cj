@NonProduct
features {}
package platform

import std.io.{InputStream, IOException}

const STDIN_FILENO: Int32 = 0
const STDOUT_FILENO: Int32 = 1
const EINTR: Int32 = 4

/**
 * The process's stdin, read straight from its file descriptor.
 *
 * @note `std.env.getStdIn()` can't serve a client: its `read` returns only once the buffer is
 * full or at EOF, even a one-byte one - so a server sending nothing until it has an answer waits
 * forever for a request that has already arrived. This returns whatever `read(2)` returns (`_read`
 * on Windows, which on a pipe returns as soon as anything has arrived just the same).
 *
 * @note The read blocks in C for as long as the editor is idle, which is only harmless because
 * the call goes through the runtime's switch to native code (C5, D13).
 */
public class StdinStream <: InputStream {
    /**
     * @throws IOException - if the read fails with anything but `EINTR`
     */
    public func read(buffer: Array<Byte>): Int64 {
        if (buffer.size == 0) {
            return 0
        }
        while (true) {
            // A workaround of the runtime's scheduler (#324): a thread `spawn`ed from here, just before
            // the read blocks in C, may never start while it blocks — it waits on this thread's run queue,
            // and no idle worker wakes to take it — so a hover could wait for the next message forever.
            // Giving way here first runs what this thread spawned or woke. To go once the SDK is fixed.
            sleep(Duration.Zero)
            let n = unsafe {
                let raw = acquireArrayRawData(buffer)
                let n = readStdin(raw.pointer, buffer.size)
                releaseArrayRawData(raw)
                n
            }
            if (n >= 0) {
                return n
            }
            let errno = lastErrno()
            if (errno != EINTR) {
                throw IOException("reading stdin failed with errno ${errno}")
            }
        }
        0
    }
}

/**
 * Makes stdin and stdout carry bytes as they are. On Windows the C runtime opens both in text
 * mode, which turns every `\n` written into `\r\n` and every `\r\n` read into `\n` - and a frame's
 * `Content-Length` counts the bytes before that. Elsewhere there is no such mode.
 */
public common func useBinaryStdio(): Unit

/**
 * `read(2)` of stdin, through a foreign function that is not `@FastNative`: one named like a C
 * library function LLVM knows (`read`, `write`, `open`, `getchar`, ...) is compiled as one, without
 * switching the thread to native code, so while it blocks the garbage collector waits for it at
 * full CPU and every other thread stops at its next allocation (C5, D13).
 */
common unsafe func readStdin(buf: CPointer<Byte>, count: Int64): Int64

/**
 * The C runtime's `errno` of this thread.
 */
common func lastErrno(): Int32
