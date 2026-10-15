package macro_host

import std.fs.{Directory, exists, File, FSException, OpenMode, Path}
import platform.tryLockFile

// A lock on a directory of a cache directory (D106): a build holds it while it writes there, so a second server on
// the same project neither builds into it nor removes it meanwhile. It is the OS's lock on an open file, `flock` or
// `LockFileEx` (`platform.tryLockFile`), which the OS releases when the process dies: none is ever left behind.
// Never waited for.

/**
 * The file a directory's lock is taken on.
 */
public const LOCK_FILE = "lock"

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
    // `create` throws for a directory that is there
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    let file = File(dir.join(LOCK_FILE), OpenMode.ReadWrite)
    if (tryLockFile(file)) {
        CacheLock(file)
    } else {
        file.close()
        None
    }
}
