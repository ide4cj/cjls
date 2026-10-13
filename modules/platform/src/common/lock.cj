@NonProduct
features {}
package platform

import std.fs.File

/**
 * Takes an exclusive lock on the open `file`, never waiting for it: `false` if another holds it, in this process
 * or another. Closing the file releases it, and so does the end of the process, however it ends: `flock` on POSIX,
 * `LockFileEx` on Windows. Neither call blocks, so neither is a blocking foreign function (C5).
 */
public common func tryLockFile(file: File): Bool
