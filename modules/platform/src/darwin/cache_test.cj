features {user.platform.posix, os.darwin}
package platform

import std.collection.HashMap
import std.fs.Path
import std.unittest.*
import std.unittest.testmacro.*

func cacheEnvOf(vars: Array<(String, String)>): (String) -> ?String {
    let map = HashMap<String, String>(vars)
    { name => map.get(name) }
}

@Test
class UserCacheDirOnMacOSTest {
    @TestCase
    func isTheHomesLibraryCaches() {
        // act, assert
        @Expect(userCacheDir(cacheEnvOf([("HOME", "/Users/u"), ("XDG_CACHE_HOME", "/xdg")])),
            Some(Path("/Users/u/Library/Caches")))
        @Expect(userCacheDir(cacheEnvOf([])), None<Path>)
    }
}
