features { os.windows }
package platform

import std.fs.File

foreign func LockFileEx(file: IntNative, flags: UInt32, reserved: UInt32, low: UInt32, high: UInt32,
    overlapped: CPointer<Overlapped>): Int32

const LOCKFILE_FAIL_IMMEDIATELY: UInt32 = 0x1

const LOCKFILE_EXCLUSIVE_LOCK: UInt32 = 0x2

/**
 * `OVERLAPPED`, whose offset says where the range locked starts: at 0.
 */
@C
struct Overlapped {
    var internal: UIntNative = 0
    var internalHigh: UIntNative = 0
    var offset: UInt32 = 0
    var offsetHigh: UInt32 = 0
    var event: CPointer<Unit> = CPointer()
}

public specific func tryLockFile(file: File): Bool {
    var overlapped = Overlapped()
    // the `HANDLE` std holds; one byte locked, at 0
    unsafe {
        LockFileEx(file.fileDescriptor.fileHandle, LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY, 0, 1, 0,
            inout overlapped)
    } != 0
}
