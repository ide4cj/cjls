features { os.windows }
package platform

import std.collection.HashMap
import std.fs.Path

public specific func sdkToolEnvironment(variables: Array<(String, String)>, libDir: Path): HashMap<String, String> {
    let path = libraryPathVariable()
    let env = HashMap<String, String>()
    for ((name, value) in variables) {
        // one `PATH`, whatever the case it came in (`Path`): Windows reads it so
        env[if (name.toAsciiUpper() == path) {
            path
        } else {
            name
        }] = value
    }
    putFirstOn(env, path, libDir)
    env
}
