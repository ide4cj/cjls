package cjo

/**
 * The major of the format this reader knows (`CJO_MAJOR_VERSION` of `include/cangjie/Modules/CjoVersion.h`):
 * a file of another major is laid out otherwise, and is not read.
 */
public const CJO_MAJOR: UInt8 = 0

/**
 * Either a value or why there is none.
 */
public enum Result<T, E> {
    | Ok(T)
    | Err(E)
}

/**
 * Why a file is not opened as a `.cjo`.
 */
public enum CjoError <: ToString {
    /** Too short for a header, or a header other than a `.cjo`'s. */
    | NotCjo
    /** No format version: a compiler older than versions wrote it. */
    | NoVersion
    /** A format of another major, which this reader does not know. */
    | ForeignMajor(UInt8)

    public func toString(): String {
        match (this) {
            case NotCjo => "not a .cjo"
            case NoVersion => "a .cjo with no format version"
            case ForeignMajor(major) => "a .cjo of format ${major}.x, not ${CJO_MAJOR}.x"
        }
    }
}

/**
 * The package `bytes` hold, if they are a `.cjo` of the format's major: its identifier and its version are
 * checked, nothing else is until it is read (`CjoException`).
 */
public func openCjo(bytes: Array<Byte>): Result<Package, CjoError> {
    if (bytes.size < 8 || bytes[4..8] != Package.FILE_IDENTIFIER.toArray()) {
        return Err(NotCjo)
    }
    let root = Int64(readUInt32(bytes, 0))
    if (root + 4 > bytes.size) {
        return Err(NotCjo)
    }
    let (pkg, version) = try {
        let pkg = Package.root(bytes)
        (pkg, pkg.cjoVersion)
    } catch (_: IndexOutOfBoundsException) {
        return Err(NotCjo)
    }
    match (version) {
        case Some(v) where v.majorNum != CJO_MAJOR => Err(ForeignMajor(v.majorNum))
        case Some(_) => Ok(pkg)
        case _ => Err(NoVersion)
    }
}
