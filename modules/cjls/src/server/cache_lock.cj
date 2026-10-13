package cjls.server

import std.fs.{File, FSException, OpenMode, Path}

// A lock on a directory of a cache directory (D106): a build holds it while it writes there, so a second server on
// the same project neither builds into it nor removes it meanwhile. It is the OS's lock on an open file, `flock` or
// `LockFileEx`, which the OS releases when the process dies: none is ever left behind. Never waited for: neither
// call blocks (`LOCK_NB`, `LOCKFILE_FAIL_IMMEDIATELY`), so neither is a blocking foreign function (C5).

/**
 * The file a directory's lock is taken on.
 */
public const LOCK_FILE = "lock"

@When[os != "Windows"]
foreign func flock(fd: Int32, operation: Int32): Int32

@When[os != "Windows"]
const LOCK_EX: Int32 = 2

@When[os != "Windows"]
const LOCK_NB: Int32 = 4

@When[os == "Windows"]
foreign func LockFileEx(file: IntNative, flags: UInt32, reserved: UInt32, low: UInt32, high: UInt32,
    overlapped: CPointer<Overlapped>): Int32

@When[os == "Windows"]
const LOCKFILE_FAIL_IMMEDIATELY: UInt32 = 0x1

@When[os == "Windows"]
const LOCKFILE_EXCLUSIVE_LOCK: UInt32 = 0x2

/**
 * `OVERLAPPED`, whose offset says where the range locked starts: at 0.
 */
@When[os == "Windows"]
@C
struct Overlapped {
    var internal: UIntNative = 0
    var internalHigh: UIntNative = 0
    var offset: UInt32 = 0
    var offsetHigh: UInt32 = 0
    var event: CPointer<Unit> = CPointer()
}

/**
 * A lock held on a directory (`tryLockCacheDir`), until it is closed or the process ends.
 */
public class CacheLock <: Resource {
    CacheLock(private let file: File) {}

    public func isClosed(): Bool {
        file.isClosed()
    }

    public func close(): Unit {
        file.close()
    }
}

/**
 * Takes the lock of the directory at `dir`, made if it is not there: `None` if another holds it, in this process or
 * another.
 *
 * @throws FSException - if its lock file cannot be opened
 */
public func tryLockCacheDir(dir: Path): ?CacheLock {
    ensureDir(dir)
    let file = File(dir.join(LOCK_FILE), OpenMode.ReadWrite)
    if (lockFile(file)) {
        CacheLock(file)
    } else {
        file.close()
        None
    }
}

@When[os != "Windows"]
func lockFile(file: File): Bool {
    unsafe { flock(Int32(file.fileDescriptor.fileHandle), LOCK_EX | LOCK_NB) } == 0
}

@When[os == "Windows"]
func lockFile(file: File): Bool {
    var overlapped = Overlapped()
    // a `HANDLE`, as std holds it
    unsafe {
        LockFileEx(file.fileDescriptor.fileHandle, LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY, 0, 1, 0,
            inout overlapped)
    } != 0
}
