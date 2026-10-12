@NonProduct
features {}
package platform

import std.fs.Path

/**
 * What separates the names of a path as the platform writes it.
 */
public common func pathSeparator(): String

/**
 * `path` as the platform's one spelling of it: on Windows with `\` and a lowercase drive letter,
 * elsewhere as it is.
 */
public common func canonicalPath(path: Path): Path

/**
 * The path of a `file:` URI's path: on Windows the drive is the first segment, `/c:/src` (RFC
 * 8089).
 */
public common func pathOfFileUriPath(uriPath: String): String

/**
 * The path of a `file:` URI for `path`: on Windows a drive goes in as a first segment, `/c:/src`.
 */
public common func fileUriPathOf(path: Path): String
