@NonProduct
features { user.platform.posix }
package platform

import std.fs.Path

foreign func uname(name: CPointer<UInt8>): Int32

/**
 * The size of each field of `struct utsname`: 65 on Linux, 256 on macOS.
 */
common func utsnameFieldSize(): Int64

/**
 * The architecture `uname` tells this process it runs as, read once, as `@When` names it: macOS's
 * `arm64` is cjc's `aarch64`. Empty if `uname` fails.
 */
let HOST_ARCH: String = match (unameMachine()) {
    case "arm64" => "aarch64"
    case machine => machine
}

public specific func hostArch(): String {
    HOST_ARCH
}

/**
 * The `machine` field of `uname`, the fifth of `struct utsname` (Linux's has a sixth, `domainname`).
 */
func unameMachine(): String {
    let size = utsnameFieldSize()
    let fields = Array<UInt8>(size * 6, repeat: 0)
    let code = unsafe {
        let raw = acquireArrayRawData(fields)
        let code = uname(raw.pointer)
        releaseArrayRawData(raw)
        code
    }
    if (code != 0) {
        return ""
    }
    let machine = fields[size * 4..size * 5]
    let end = machine.indexOf(0) ?? machine.size
    String.fromUtf8(machine[..end])
}

public specific func executableFile(name: String): String {
    name
}

public specific func pathListSeparator(): String {
    ":"
}

public specific func dumpsHeap(): Bool {
    true
}

public specific func pathSeparator(): String {
    "/"
}

public specific func canonicalPath(path: Path): Path {
    path
}

public specific func pathOfFileUriPath(uriPath: String): String {
    uriPath
}

public specific func fileUriPathOf(path: Path): String {
    path.toString()
}
