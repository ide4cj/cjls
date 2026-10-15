features { os.windows }
package platform

import std.fs.Path

public specific func userCacheDir(env: (String) -> ?String): ?Path {
    env("LOCALAPPDATA").filter {dir => !dir.isEmpty()}.map {dir => Path(dir)}
}
