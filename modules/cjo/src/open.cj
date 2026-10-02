package cjo

/**
 * The major of the format this reader knows (`CJO_MAJOR_VERSION` of `include/cangjie/Modules/CjoVersion.h`):
 * a file of another major is laid out otherwise, and is not read.
 */
public const CJO_MAJOR: UInt8 = 0

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
 * A file `openCjo` does not open, and why.
 */
public class CjoOpenException <: CjoException {
    public CjoOpenException(public let error: CjoError) {
        super(error.toString())
    }

    protected override func getClassName(): String {
        "CjoOpenException"
    }
}

/**
 * The package `bytes` hold: its identifier and the major of its version are checked, nothing else is until it
 * is read (`CjoException`).
 *
 * @throws CjoOpenException - if `bytes` are not a `.cjo` of the format's major
 */
public func openCjo(bytes: Array<Byte>): Package {
    if (bytes.size < 8 || bytes[4..8] != Package.FILE_IDENTIFIER.toArray()) {
        throw CjoOpenException(NotCjo)
    }
    let root = Int64(readUInt32(bytes, 0))
    if (root + 4 > bytes.size) {
        throw CjoOpenException(NotCjo)
    }
    let (pkg, version) = try {
        let pkg = Package.root(bytes)
        (pkg, pkg.cjoVersion)
    } catch (_: IndexOutOfBoundsException) {
        throw CjoOpenException(NotCjo)
    }
    match (version) {
        case Some(v) where v.majorNum != CJO_MAJOR => throw CjoOpenException(ForeignMajor(v.majorNum))
        case Some(_) => pkg
        case _ => throw CjoOpenException(NoVersion)
    }
}
