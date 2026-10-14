features { user.platform.posix, os.linux }
package platform

import std.collection.HashMap
import std.fs.Path

public specific func sdkToolEnvironment(variables: Array<(String, String)>, libDir: Path): HashMap<String, String> {
    let env = HashMap<String, String>(variables)
    putFirstOn(env, libraryPathVariable(), libDir)
    env
}
