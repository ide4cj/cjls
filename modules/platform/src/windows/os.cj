features {os.windows}
package platform

import std.fs.Path

public specific func hostOs(): String {
    "Windows"
}

public specific func hostEnv(): String {
    "gnu"
}

public specific func sharedLibrarySuffix(): String {
    ".dll"
}

public specific func libraryPathVariable(): String {
    "PATH"
}

public specific func executableFile(name: String): String {
    "${name}.exe"
}

public specific func pathListSeparator(): String {
    ";"
}

public specific func dumpsHeap(): Bool {
    false
}

public specific func pathSeparator(): String {
    "\\"
}

public specific func canonicalPath(path: Path): Path {
    let text = path.toString().replace("/", "\\")
    if (text.size >= 2 && text[1] == b':') {
        Path(text[..1].toAsciiLower() + text[1..])
    } else {
        Path(text)
    }
}

public specific func pathOfFileUriPath(uriPath: String): String {
    if (uriPath.size >= 3 && uriPath[2] == b':') { uriPath[1..] } else { uriPath }
}

public specific func fileUriPathOf(path: Path): String {
    "/" + path.toString().replace("\\", "/")
}
