features {user.platform.posix, os.darwin}
package platform

import std.fs.Path

public specific func userCacheDir(env: (String) -> ?String): ?Path {
    env("HOME")
        .filter { dir => !dir.isEmpty() }
        .map { dir => Path(dir).join("Library").join("Caches") }
}
