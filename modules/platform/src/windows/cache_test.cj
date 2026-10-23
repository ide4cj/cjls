features {os.windows}
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
class UserCacheDirOnWindowsTest {
    @TestCase
    func isLocalAppData() {
        // act, assert
        @Expect(userCacheDir(cacheEnvOf([("LOCALAPPDATA", "C:\\Users\\u\\AppData\\Local"), ("HOME", "C:\\Users\\u")])),
            Some(Path("C:\\Users\\u\\AppData\\Local")))
        @Expect(userCacheDir(cacheEnvOf([])), None<Path>)
    }
}
