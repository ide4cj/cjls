package loupe

import std.env.getTempDirectory
import std.fs.*
import std.time.DateTime
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.{BinaryModel, BinarySources, PackageModel}
import loupe.fixture.*
import loupe.vfs.VfsPath

/**
 * Checks where the name at the cursor of `fixture` is declared, with std's packages `packages` read
 * from the SDK and their sources from `.corpora/`: each target as its file under std's sources, the
 * line its name is on, and its name.
 */
func checkDefinitionInStd(fixture: String, packages: Array<String>, expected: Array<String>): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database(binaries: packages.map {name => stdCjoRead(name, stdCjo(name))},
        models: [stdWithSources(packages)])
    let cursor = parsed.cursor ?? throw FixtureException("no $0 in the fixture")
    let dir = stdSourcesDir()
    let found = definitionAt(db, cursor.fileId, cursor.offset).map {
        target =>
        let text = db.sourceFile(target.fileId).getOrThrow().text(db)
        let line = text.lineOf(target.focusRange.start)
        let path = String.join(parsed.pathOf(target.fileId).segmentsUnder(dir).getOrThrow(), delimiter: "/")
        let written = text.slice(text.lineStart(line)..text.lineEnd(line)).toString().trimAscii()
        let name = text.slice(target.focusRange.start..target.focusRange.end).toString()
        @Expect(target.fullRange.start <= target.focusRange.start && target.focusRange.end <= target.fullRange.end)
        "${path}: ${name} in `${written}`"
    }
    @Expect(found, expected)
}

@Test
class DefinitionBinaryTest {
    @TestCase
    func aTypeOfStdInASignatureGoesToItsSource() {
        checkDefinitionInStd(#"
            //- /main.cj module=m package=m
            package m
            func f(x: $0String): Unit {}
            "#, ["std.core"],
            ["core/string.cj: String in `public struct String <: Collection<Byte> & Comparable<String> & Hashable & ToString {`"])
    }

    @TestCase
    func aFunctionOfStdCalledGoesToItsSource() {
        checkDefinitionInStd(#"
            //- /main.cj module=m package=m
            package m
            main() {
                $0println("x")
            }
            "#, ["std.core"], ["core/print.cj: println in `public func println(str: String): Unit {`"])
    }

    @TestCase
    func theOverloadOfAMethodOfStdACallTakesGoesToItsSource() {
        checkDefinitionInStd(#"
            //- /main.cj module=m package=m
            package m
            import std.collection.ArrayList
            main() {
                let list = ArrayList<Int64>()
                list.$0add(1)
            }
            "#, ["std.core", "std.collection"],
            ["collection/array_list.cj: add in `public func add(element: T): Unit {`"])
    }

    @TestCase
    func aMemberOfAnExtendInStdGoesToItsSource() {
        checkDefinitionInStd(#"
            //- /main.cj module=m package=m
            package m
            main() {
                let n: Int64 = 1
                n.$0toString()
            }
            "#, ["std.core"], ["core/to_string.cj: toString in `public func toString(): String {`"])
    }

    @TestCase
    func aNameInBackquotesGoesToTheNameInside() {
        checkDefinitionInStd(#"
            //- /main.cj module=m package=m
            package m
            import std.posix.*
            main() {
                $0`open`("x", 0)
            }
            "#, ["std.core", "std.posix"], ["posix/file_dir.cj: open in `public func `open`(path: String, oflag: Int32): Int32 {`"])
    }

    @TestCase
    func sourcesOfAnotherVersionGiveNoDefinition() {
        // arrange
        let dir = getTempDirectory().join("cjls-other-std-${DefinitionBinaryTest.uniqueSuffix()}")
        let core = dir.join("core")
        Directory.create(core, recursive: true)
        // std's files, long enough, with nothing where the `.cjo` says its declarations are
        for (info in Directory.readFrom(stdSourcesDir().filePath.getOrThrow().join("core")) where info.isRegular()) {
            File.writeTo(core.join(info.name), ("package std.core\n" + "//\n" * 5000).toArray())
        }
        let files = Directory.readFrom(core).map {info => VfsPath.file(core.join(info.name))}
        let other = BinaryModel("std", [],
            sources: BinarySources(VfsPath.file(dir), [PackageModel("std.core", VfsPath.file(core), files)]))
        let parsed = Fixture.parse(#"
            //- /main.cj module=m package=m
            package m
            func f(x: $0String): Unit {}
            "#)
        let db = parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))], models: [other])
        let cursor = parsed.cursor.getOrThrow()

        // act
        let targets = definitionAt(db, cursor.fileId, cursor.offset)

        // assert
        @Expect(targets.isEmpty())
        removeIfExists(dir, recursive: true)
    }

    static func uniqueSuffix(): String {
        "${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
    }
}
