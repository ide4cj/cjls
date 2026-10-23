@NonProduct
features {user.platform.posix}
package platform

// Not `read`: see `readStdin`.
foreign func readv(fd: Int32, iov: CPointer<IoVec>, iovcnt: Int32): IntNative

@C
struct IoVec {
    var base: CPointer<Byte>
    var len: UIntNative
    init(base: CPointer<Byte>, len: UIntNative) {
        this.base = base
        this.len = len
    }
}

public specific func useBinaryStdio(): Unit {}

/**
 * `read(2)` as `readv` of one buffer: `readv` is not a name LLVM knows.
 */
specific unsafe func readStdin(buf: CPointer<Byte>, count: Int64): Int64 {
    var iov = IoVec(buf, UIntNative(count))
    Int64(readv(STDIN_FILENO, inout iov, 1))
}
