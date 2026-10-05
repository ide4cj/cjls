package loupe.fixture

import std.env.{getTempDirectory, getVariable}
import std.fs.*
import std.time.DateTime
import loupe.vfs.{CjoFile, CjoFileRead, FileStamp, VfsPath}

/**
 * The bytes of `<name>.cjo` of the SDK's std, of whichever target it has first.
 */
public func stdCjo(name: String): Array<Byte> {
    let home = Path(getVariable("CANGJIE_HOME") ?? throw IllegalStateException("CANGJIE_HOME names no SDK"))
    for (target in Directory.readFrom(home.join("modules")) where target.isDirectory()) {
        let file = target.path.join("std").join("${name}.cjo")
        if (exists(file)) {
            return File.readFrom(file)
        }
    }
    throw IllegalStateException("no ${name}.cjo under ${home.join("modules")}")
}

/**
 * `bytes` as the `.cjo` of the package `name` of `std`, read: what a project's binaries are.
 */
public func stdCjoRead(name: String, bytes: Array<Byte>): CjoFileRead {
    let file = CjoFile("std", name, VfsPath.file(getTempDirectory().join("${name}.cjo")))
    CjoFileRead(file, FileStamp(bytes.size, DateTime.now()), bytes)
}
