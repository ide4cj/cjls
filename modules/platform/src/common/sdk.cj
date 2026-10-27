@NonProduct
features {}
package platform

import std.collection.HashMap
import std.fs.Path

/**
 * The environment a tool of the SDK (`cjc`) runs under, as the SDK's `envsetup` sets it: `variables` with
 * `libDir` first where the platform looks for shared libraries (`LD_LIBRARY_PATH`, `DYLD_LIBRARY_PATH`, `PATH`
 * whatever its case), and on macOS `SDKROOT` from `xcrun` when `variables` name none: without it cjc links with
 * `-syslibroot /`, where there is no `libSystem`, and fails.
 */
public common func sdkToolEnvironment(
    variables: Array<(String, String)>,
    libDir: Path
): HashMap<String, String>

/**
 * `env` with `dir` first on the list of directories `name` holds.
 */
func putFirstOn(env: HashMap<String, String>, name: String, dir: Path): Unit {
    env[name] =
        match (env.get(name)) {
            case Some(old) where !old.isEmpty() => "${dir}${pathListSeparator()}${old}"
            case _ => dir.toString()
        }
}
