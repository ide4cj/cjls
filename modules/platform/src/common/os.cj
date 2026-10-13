@NonProduct
features {}
package platform

/**
 * The platform the server runs on, as `@When` names it: `Linux`, `macOS`, `Windows`.
 */
public common func hostOs(): String

/**
 * The environment of the targets cjls is built for, as cjc names it: `gnu` on Linux and on Windows
 * (`mingw32`), none on macOS.
 */
public common func hostEnv(): String

/**
 * The architecture, as `@When` names it. cjpm has no feature for it, only `os.*`: a source set
 * cannot tell it, `@When` can.
 */
@When[arch == "aarch64"]
public func hostArch(): String {
    "aarch64"
}

@When[arch == "x86_64"]
public func hostArch(): String {
    "x86_64"
}

/**
 * The file an executable named `name` is in: `name.exe` on Windows.
 */
public common func executableFile(name: String): String

/**
 * What separates the directories of `PATH`: `;` on Windows, `:` elsewhere.
 */
public common func pathListSeparator(): String

/**
 * Whether the runtime here dumps its heap: on Windows `dumpHeapData` never returns, with the
 * nightlies of 2026-09-18 and 09-29 alike, while `gc(heavy: true)` does (#64).
 */
public common func dumpsHeap(): Bool
