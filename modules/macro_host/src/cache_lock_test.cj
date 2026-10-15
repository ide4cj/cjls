package macro_host

import std.env.getTempDirectory
import std.fs.Directory
import std.unittest.*
import std.unittest.testmacro.*

@Test
class CacheLockTest {
    @TestCase
    func aDirectoryLockedIsNotLockedAgainUntilClosed() {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        let first = tryLockCacheDir(dir).getOrThrow()

        // act
        let whileHeld = tryLockCacheDir(dir)
        first.close()
        let afterwards = tryLockCacheDir(dir)

        // assert
        @Expect(whileHeld.isNone())
        @Expect(afterwards.isSome())
        afterwards?.close()
    }
}
