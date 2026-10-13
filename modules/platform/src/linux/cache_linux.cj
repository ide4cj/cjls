features { user.platform.posix, os.linux }
package platform

import std.fs.Path

public specific func userCacheDir(env: (String) -> ?String): ?Path {
    match (env("XDG_CACHE_HOME").filter {dir => !dir.isEmpty() && Path(dir).isAbsolute()}) {
        case Some(dir) => Path(dir)
        case None => env("HOME").filter {dir => !dir.isEmpty()}.map {dir => Path(dir).join(".cache")}
    }
}
