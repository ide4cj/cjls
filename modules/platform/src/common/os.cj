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
 * The architecture, as `@When` names it: each OS's set gives it, as the workspace is built for one
 * triple per OS, those it names stdx for. cjpm deduces a feature of the OS alone, and a set has one
 * set above it: the architecture can be no set of its own.
 */
public common func hostArch(): String

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

/**
 * What ends the name of a shared library, a macro package's as cjc writes it: `.dylib` on macOS,
 * `.so` on Linux, `.dll` on Windows.
 */
public common func sharedLibrarySuffix(): String

/**
 * The variable of the environment the loader finds shared libraries by: `DYLD_LIBRARY_PATH` on
 * macOS, `LD_LIBRARY_PATH` on Linux, `PATH` on Windows.
 */
public common func libraryPathVariable(): String
