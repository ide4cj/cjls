@NonProduct
features {}
package platform

import std.fs.Path

/**
 * The user's cache directory, as the environment `env` names it: `$XDG_CACHE_HOME`, if it is absolute, else
 * `~/.cache` on Linux; `~/Library/Caches` on macOS; `%LOCALAPPDATA%` on Windows. `None` if it names none.
 */
public common func userCacheDir(env: (String) -> ?String): ?Path
