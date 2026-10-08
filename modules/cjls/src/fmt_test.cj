package cjls

import std.env.getTempDirectory
import std.fs.{Directory, File, FSException, Path}
import std.io.{ByteBuffer, readToEnd}

/**
 * What was written to `buffer`, read out of it: a second call has nothing.
 */
func written(buffer: ByteBuffer): String {
    String.fromUtf8(readToEnd(buffer))
}

@Test
class FormatPathsTest {
    @TestCase
    func aDirectorysFilesAreFormattedInPlaceAndNamed() {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        Directory.create(dir.join("src"))
        File.writeTo(dir.join("src").join("a.cj"), "func f() {\nx\n}\n".toArray())
        File.writeTo(dir.join("b.cj"), "let b = 1\n".toArray())
        let (out, err) = (ByteBuffer(), ByteBuffer())

        // act
        let exitCode = formatPaths([dir], false, out, err)

        // assert
        @Expect(exitCode, 0)
        @Expect(String.fromUtf8(File.readFrom(dir.join("src").join("a.cj"))), "func f() {\n    x\n}\n")
        // as the server names it, which on some systems is not as the test does
        let named = written(out)
        @Expect(named.split("\n", removeEmpty: true).size, 1)
        @Expect(named.endsWith("a.cj\n"))
        @Expect(written(err), "")
    }

    @TestCase
    func checkChangesNothingAndFailsForAFileToChange() {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        let file = dir.join("a.cj")
        File.writeTo(file, "func f() {\nx\n}\n".toArray())
        let (out, err) = (ByteBuffer(), ByteBuffer())

        // act
        let exitCode = formatPaths([file], true, out, err)

        // assert
        @Expect(exitCode, 1)
        @Expect(String.fromUtf8(File.readFrom(file)), "func f() {\nx\n}\n")
        @Expect(written(out).endsWith("a.cj\n"))
    }

    @TestCase
    func aFileWithSyntaxErrorsOrAPathNotThereFails() {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        let file = dir.join("a.cj")
        File.writeTo(file, "func f( {\n".toArray())
        let (out, err) = (ByteBuffer(), ByteBuffer())

        // act
        let exitCode = formatPaths([file, dir.join("none.cj")], false, out, err)

        // assert
        @Expect(exitCode, 1)
        @Expect(String.fromUtf8(File.readFrom(file)), "func f( {\n")
        @Expect(written(out), "")
        let lines = written(err).split("\n", removeEmpty: true)
        @Expect(lines.size, 2)
        @Expect(lines[0], "${dir.join("none.cj")}: no such file or directory")
        @Expect(lines[1].endsWith("a.cj: not formatted: it has syntax errors"))
    }

    @TestCase
    func aFileNotWrittenIsNamedOnErrAndFails() {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        let file = dir.join("a.cj")
        File.writeTo(file, "func f() {\nx\n}\n".toArray())
        let (out, err) = (ByteBuffer(), ByteBuffer())

        // act
        let exitCode = formatPaths([file], false, out, err,
            write: {_, _ => throw FSException("Permission denied")})

        // assert
        @Expect(exitCode, 1)
        @Expect(written(out), "")
        @Expect(written(err).endsWith("a.cj: not written: Permission denied\n"))
    }
}
