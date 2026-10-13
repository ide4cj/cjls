@NonProduct
features { user.platform.posix }
package platform

import std.fs.File

foreign func flock(fd: Int32, operation: Int32): Int32

public specific func tryLockFile(file: File): Bool {
    // LOCK_EX | LOCK_NB, the same on Linux and macOS
    unsafe { flock(Int32(file.fileDescriptor.fileHandle), 2 | 4) } == 0
}
