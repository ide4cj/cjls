features { os.windows }
package platform

foreign func _read(fd: Int32, buf: CPointer<Byte>, count: UInt32): Int32

foreign func _setmode(fd: Int32, mode: Int32): Int32

foreign func _errno(): CPointer<Int32>

public specific func useBinaryStdio(): Unit {
    // _O_BINARY
    let binary: Int32 = 0x8000
    unsafe {
        _setmode(STDIN_FILENO, binary)
        _setmode(STDOUT_FILENO, binary)
    }
}

/**
 * `_read` is not a name LLVM knows, so it can block (D13).
 */
specific unsafe func readStdin(buf: CPointer<Byte>, count: Int64): Int64 {
    // `_read` takes an unsigned int, and a buffer is never near 4 GiB
    Int64(_read(STDIN_FILENO, buf, UInt32(count)))
}

specific func lastErrno(): Int32 {
    unsafe { _errno().read() }
}
