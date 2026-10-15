features { user.platform.posix, os.linux }
package platform

import std.collection.HashMap
import std.fs.Path
import std.unittest.*
import std.unittest.testmacro.*

func cacheEnvOf(vars: Array<(String, String)>): (String) -> ?String {
    let map = HashMap<String, String>(vars)
    {name => map.get(name)}
}

@Test
class UserCacheDirOnLinuxTest {
    @TestCase
    func isAnAbsoluteXdgCacheHomeElseTheHomesCache() {
        // act, assert
        @Expect(userCacheDir(cacheEnvOf([("HOME", "/home/u"), ("XDG_CACHE_HOME", "/xdg")])), Some(Path("/xdg")))
        @Expect(userCacheDir(cacheEnvOf([("HOME", "/home/u"), ("XDG_CACHE_HOME", "relative")])),
            Some(Path("/home/u/.cache")))
        @Expect(userCacheDir(cacheEnvOf([])), None<Path>)
    }
}
