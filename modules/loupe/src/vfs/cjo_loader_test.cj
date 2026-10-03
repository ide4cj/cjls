package loupe.vfs

import std.env.{getTempDirectory, getVariable}
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * The bytes of `<name>.cjo` of the SDK's std, of whichever target it has first.
 */
func sdkCjo(name: String): Array<Byte> {
    let home = Path(getVariable("CANGJIE_HOME") ?? throw IllegalStateException("CANGJIE_HOME names no SDK"))
    for (target in Directory.readFrom(home.join("modules")) where target.isDirectory()) {
        let file = target.path.join("std").join("${name}.cjo")
        if (exists(file)) {
            return File.readFrom(file)
        }
    }
    throw IllegalStateException("no ${name}.cjo under ${home.join("modules")}")
}

/**
 * A directory of its own under the temporary one, holding the `.cjo` of std's `std.crypto` as
 * `std.crypto.cjo`, and the files of `others` (names and bytes).
 */
func cjoDir(others!: Array<(String, Array<Byte>)> = []): Path {
    let dir = tree([])
    File.writeTo(dir.join("std.crypto.cjo"), sdkCjo("std.crypto"))
    for ((name, bytes) in others) {
        File.writeTo(dir.join(name), bytes)
    }
    dir
}

@Test
class CjoLoaderTest {
    @TestCase
    func everyCjoOfADirectoryIsAPackageNamedAsItsFile() {
        // arrange
        let dir = tree([("std.io.cjo", ""), ("std.core.cjo", ""), ("libstd.core.a", ""), ("sub/std.deep.cjo", "")])

        // act
        let files = cjoFilesIn("std", VfsPath.file(dir))
        remove(dir, recursive: true)

        // assert
        @Expect(files.map {file => file.name}, ["std.core", "std.io"])
        @Expect(files.map {file => file.binary}, ["std", "std"])
        @Expect(files[0].path, VfsPath.file(dir.join("std.core.cjo")))
    }

    @TestCase
    func aDirectoryThatIsNotThereHasNoPackages() {
        // act, assert
        @Expect(cjoFilesIn("std", VfsPath.file(getTempDirectory().join("no-such-cjls-dir"))).isEmpty())
    }

    @TestCase
    func aCjoIsReadWithItsStamp() {
        // arrange
        let dir = cjoDir()
        let file = CjoFile("std", "std.crypto", VfsPath.file(dir.join("std.crypto.cjo")))

        // act
        let read = readCjoFiles([file, file])
        remove(dir, recursive: true)

        // assert - the same path once
        @Expect(read.files.size, 1)
        @Expect(read.files[0].file, file)
        @Expect(read.files[0].bytes, Some(sdkCjo("std.crypto")))
        @Expect(read.files[0].stamp.size, sdkCjo("std.crypto").size)
        @Expect(read.size, sdkCjo("std.crypto").size)
        @Expect(read.problems.isEmpty())
        @Expect(!read.truncated)
    }

    @TestCase
    func aCjoUnchangedIsNotReadAgainAndTakesItsSizeOfTheBudget() {
        // arrange
        let dir = cjoDir()
        let file = CjoFile("std", "std.crypto", VfsPath.file(dir.join("std.crypto.cjo")))
        let stamp = readCjoFiles([file]).files[0].stamp

        // act
        let read = readCjoFiles([file], unchanged: {_, now => now == stamp})
        remove(dir, recursive: true)

        // assert
        @Expect(read.files[0].bytes, None<Array<Byte>>)
        @Expect(read.files[0].stamp, stamp)
        @Expect(read.size, stamp.size)
    }

    @TestCase
    func aFileThatIsNoCjoIsLeftOutAndSaidSo() {
        // arrange
        let dir = cjoDir(others: [("std.text.cjo", "not a cjo".toArray())])
        let files = cjoFilesIn("std", VfsPath.file(dir))

        // act
        let read = readCjoFiles(files)
        remove(dir, recursive: true)

        // assert
        @Expect(read.files.map {it => it.file.name}, ["std.crypto"])
        @Expect(read.problems.size, 1)
        @Expect(read.problems[0].contains("std.text.cjo: not a .cjo"))
    }

    @TestCase
    func aCjoThatDoesNotFitInTheBudgetIsLeftOut() {
        // arrange
        let dir = cjoDir(others: [("std.small.cjo", sdkCjo("std.crypto")[..8])])
        let files = cjoFilesIn("std", VfsPath.file(dir))

        // act
        let read = readCjoFiles(files, budget: 100)
        remove(dir, recursive: true)

        // assert - the small one fits, but is no `.cjo`
        @Expect(read.files.isEmpty())
        @Expect(read.truncated)
        @Expect(read.problems.size, 1)
    }

    @TestCase
    func aFileThatIsNotThereIsLeftOut() {
        // act
        let read = readCjoFiles([CjoFile("std", "std.gone", VfsPath.file(getTempDirectory().join("no-such-cjls-dir").join("std.gone.cjo")))])

        // assert
        @Expect(read.files.isEmpty())
        @Expect(read.problems.isEmpty())
    }
}
