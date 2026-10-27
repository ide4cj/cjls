features {user.platform.posix, os.darwin}
package platform

import std.collection.HashMap
import std.fs.Path
import std.process.{ProcessException, executeWithOutput}

public specific func sdkToolEnvironment(
    variables: Array<(String, String)>,
    libDir: Path
): HashMap<String, String> {
    let env = HashMap<String, String>(variables)
    putFirstOn(env, libraryPathVariable(), libDir)
    if (!env.contains("SDKROOT")) {
        if (let Some(root) <- macosSdkRoot()) {
            env["SDKROOT"] = root
        }
    }
    env
}

/**
 * The macOS SDK `xcrun` finds, as `envsetup` asks for it; `None` without one (no Xcode or Command Line Tools).
 */
func macosSdkRoot(): ?String {
    try {
        let (code, out, _) =
            executeWithOutput("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-path"])
        let root = String.fromUtf8(out).trimAscii()
        if (code == 0 && !root.isEmpty()) { root } else { None }
    } catch (_: ProcessException) {
        None
    }
}
