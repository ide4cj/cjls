package cjo

/**
 * The major of the format this reader knows (`CJO_MAJOR_VERSION` of `include/cangjie/Modules/CjoVersion.h`):
 * a file of another major is laid out otherwise, and is not read.
 */
public const CJO_MAJOR: UInt8 = 0

/**
 * Bytes that are not a `.cjo`: too short for a header, or a header other than a `.cjo`'s.
 */
public class NotCjoException <: CjoException {
    public init() {
        super("not a .cjo")
    }

    protected override func getClassName(): String {
        "NotCjoException"
    }
}

/**
 * A `.cjo` of a format this reader does not know: of another `major`, or of none, written by a compiler
 * older than versions (`None`).
 */
public class CjoVersionException <: CjoException {
    public CjoVersionException(public let major: ?UInt8) {
        super(
            match (major) {
                case Some(m) => "a .cjo of format ${m}.x, not ${CJO_MAJOR}.x"
                case None => "a .cjo with no format version"
            }
        )
    }

    protected override func getClassName(): String {
        "CjoVersionException"
    }
}

/**
 * The package `bytes` hold: its identifier and the major of its version are checked, nothing else is until it
 * is read (`CjoException`).
 *
 * @throws NotCjoException - if `bytes` are not a `.cjo`
 * @throws CjoVersionException - if they are one of another major, or of none
 */
public func openCjo(bytes: Array<Byte>): Package {
    if (bytes.size < 8 || bytes[4..8] != Package.FILE_IDENTIFIER.toArray()) {
        throw NotCjoException()
    }
    let root = Int64(readUInt32(bytes, 0))
    if (root + 4 > bytes.size) {
        throw NotCjoException()
    }
    let (pkg, version) = try {
        let pkg = Package.root(bytes)
        (pkg, pkg.cjoVersion)
    } catch (_: IndexOutOfBoundsException) {
        throw NotCjoException()
    }
    match (version) {
        case Some(v) where v.majorNum != CJO_MAJOR => throw CjoVersionException(v.majorNum)
        case Some(_) => pkg
        case _ => throw CjoVersionException(None)
    }
}
