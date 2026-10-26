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
 * Finds where the name at the cursor of `fixture` is declared, with std's packages `packages` read
 * from the SDK and their sources from `.corpora/`: each target as its file under std's sources, the
 * line its name is on, and its name.
 */
func definitionsInStd(fixture: String, packages: Array<String>): Array<String> {
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
    found
}

/**
 * Checks SDK navigation for fixtures shared by the other definition test classes.
 */
func checkDefinitionInStd(fixture: String, packages: Array<String>, expected: Array<String>): Unit {
    @Expect(definitionsInStd(fixture, packages), expected)
}

@Test
class DefinitionBinaryTest {
    @TestCase
    func navigationContinuesFromTheStdDeclarationReachedFromAProject() {
        // arrange
        let parsed = Fixture.parse(#"
            //- /main.cj module=m package=m
            package m
            main() { $0println("x") }
            "#)
        let db = parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))],
            models: [stdWithSources(["std.core"])])
        let cursor = parsed.cursor ?? throw FixtureException("no $0 in the fixture")
        let targets = definitionAt(db, cursor.fileId, cursor.offset)
        @Assert(targets.size, 1)
        let target = targets[0]
        let text = (db.sourceFile(target.fileId) ?? throw FixtureException("no source for println")).text(db).toString()
        let parameter = text[target.focusRange.start..].indexOf("str: String") ??
            throw FixtureException("println has no str: String")
        let at = target.focusRange.start + parameter + 5

        // act
        let next = definitionAt(db, target.fileId, at)
        let again = definitionAt(db, cursor.fileId, cursor.offset)

        // assert
        @Assert(next.size, 1)
        @Expect(parsed.pathOf(next[0].fileId), stdSourcesDir().join("core").join("string.cj"))
        @Expect(again, targets)
    }

    @TestCase
    func aMacroOfStdCalledWithoutAnAttributeGoesToItsOverloadOfOneParameter() {
        // arrange
        const FIXTURE = #"
            //- /main.cj module=m package=m
            package m
            import std.unittest.testmacro.*
            @$0Test
            class C {}
            "#
        let packages = ["std.core", "std.ast", "std.unittest.testmacro"]
        let expected = ["unittest/testmacro/test_macro.cj: Test in `public macro Test(input: Tokens): Tokens {`"]

        // act
        let found = definitionsInStd(FIXTURE, packages)

        // assert
        @Expect(found, expected)
    }

    @TestCase
    func aMacroOfStdCalledWithAnAttributeGoesToItsOverloadOfTwo() {
        // arrange
        const FIXTURE = #"
            //- /main.cj module=m package=m
            package m
            import std.unittest.testmacro.*
            @$0Test[x in [1]]
            func f(x: Int64): Unit {}
            "#
        let packages = ["std.core", "std.ast", "std.unittest.testmacro"]
        let expected = ["unittest/testmacro/test_macro.cj: Test in `public macro Test(dsl: Tokens, input: Tokens): Tokens {`"]

        // act
        let found = definitionsInStd(FIXTURE, packages)

        // assert
        @Expect(found, expected)
    }

    @TestCase
    func aTypeOfStdInASignatureGoesToItsSource() {
        // arrange
        const FIXTURE = #"
            //- /main.cj module=m package=m
            package m
            func f(x: $0String): Unit {}
            "#
        let packages = ["std.core"]
        let expected = ["core/string.cj: String in `public struct String <: Collection<Byte> & Comparable<String> & Hashable & ToString {`"]

        // act
        let found = definitionsInStd(FIXTURE, packages)

        // assert
        @Expect(found, expected)
    }

    @TestCase
    func aFunctionOfStdCalledGoesToItsSource() {
        // arrange
        const FIXTURE = #"
            //- /main.cj module=m package=m
            package m
            main() {
                $0println("x")
            }
            "#
        let packages = ["std.core"]
        let expected = ["core/print.cj: println in `public func println(str: String): Unit {`"]

        // act
        let found = definitionsInStd(FIXTURE, packages)

        // assert
        @Expect(found, expected)
    }

    @TestCase
    func theOverloadOfAMethodOfStdACallTakesGoesToItsSource() {
        // arrange
        const FIXTURE = #"
            //- /main.cj module=m package=m
            package m
            import std.collection.ArrayList
            main() {
                let list = ArrayList<Int64>()
                list.$0add(1)
            }
            "#
        let packages = ["std.core", "std.collection"]
        let expected = ["collection/array_list.cj: add in `public func add(element: T): Unit {`"]

        // act
        let found = definitionsInStd(FIXTURE, packages)

        // assert
        @Expect(found, expected)
    }

    @TestCase
    func aMemberOfAnExtendInStdGoesToItsSource() {
        // arrange
        const FIXTURE = #"
            //- /main.cj module=m package=m
            package m
            main() {
                let n: Int64 = 1
                n.$0toString()
            }
            "#
        let packages = ["std.core"]
        let expected = ["core/to_string.cj: toString in `public func toString(): String {`"]

        // act
        let found = definitionsInStd(FIXTURE, packages)

        // assert
        @Expect(found, expected)
    }

    @TestCase
    func aNameInBackquotesGoesToTheNameInside() {
        // arrange
        const FIXTURE = #"
            //- /main.cj module=m package=m
            package m
            import std.posix.*
            main() {
                $0`open`("x", 0)
            }
            "#
        let packages = ["std.core", "std.posix"]
        let expected = ["posix/file_dir.cj: open in `public func `open`(path: String, oflag: Int32): Int32 {`"]

        // act
        let found = definitionsInStd(FIXTURE, packages)

        // assert
        @Expect(found, expected)
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
