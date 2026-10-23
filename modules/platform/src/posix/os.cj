@NonProduct
features {user.platform.posix}
package platform

import std.fs.Path

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
