package loupe.hir

import std.collection.*
import std.sync.AtomicInt64
import std.unittest.*
import std.unittest.testmacro.*
import calca.*
import calca.macros.*
import ginkgo.{SyntaxElement, TextRange}
import cjsyntax.ast.identText
import rope.Rope
import loupe.db.{AnalysisDatabase, Package, SourceFile}
import loupe.fixture.*
import loupe.syntax.parse
import loupe.vfs.FileId

/**
 * The source package `file` of a fixture is in.
 */
func sourcePackageOf(db: AnalysisDatabase, file: FixtureFile): Package {
    match (packageOf(db, file)) {
        case Source(pkg) => pkg
        case Binary(_) => throw FixtureException("${file.pkg} is a binary")
    }
}

/**
 * Checks what the name at the cursor of `fixture`, used in `ns`, means in its file is its
 * annotations: `//^ def` under each declaration found, `//^ ambiguous` under each candidate of an
 * ambiguity, `//^ ctor` and `//^ imported ctor` under constructors; under the name, `//^ package p`,
 * `//^ ambiguous package p` or `//^ not found`.
 */
func checkScope(fixture: String, ns!: Namespace = Namespace.Values): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database()
    let cursor = parsed.cursor ?? throw FixtureException("no $0 in the fixture")
    let file = parsed.files.iterator().filter {file => file.fileId == cursor.fileId}.next().getOrThrow()
    let source = db.sourceFile(file.fileId).getOrThrow()
    var use: ?(String, TextRange) = None
    for (element in parse(db, source).syntaxNode().descendantsWithTokens()) {
        if (let SyntaxElement.Token(token) <- element) {
            if (token.textRange.start <= cursor.offset && cursor.offset < token.textRange.end) {
                use = (identText(token), token.textRange)
            }
        }
    }
    let (name, range) = use ?? throw FixtureException("no token at $0")
    let pkg = sourcePackageOf(db, file)
    let resolution = lookUp(db, pkg, source, name, ns)
    let onDecl = {id: DefId, text: String => annotationOn(db, id, nameOfDef(db, id), text)}
    let annotations: Array<Annotation> = match (resolution) {
        case Found(ids) => ids.map {id => onDecl(id, "def")}
        case FoundPackage(found) => [Annotation(file.fileId, range, "package ${nameOf(db, found)}")]
        case Ambiguous(targets) => targets.map {
            target => match (target) {
                case OfDecl(id) => onDecl(id, "ambiguous")
                case OfPackage(found) => Annotation(file.fileId, range, "ambiguous package ${nameOf(db, found)}")
            }
        }
        case Ctors(own, imported) => own.map {id => onDecl(id, "ctor")}.concat(imported.map {id => onDecl(id, "imported ctor")})
        case NotFound => [Annotation(file.fileId, range, "not found")]
    }
    expectAnnotations(fixture, annotations)
}

/**
 * The first name `id` declares, a member's too.
 */
func nameOfDef(db: AnalysisDatabase, id: DefId): String {
    let wanted = id.item(db)
    func find(items: Array<Item>): ?String {
        for (item in items) {
            if (item.id == wanted) {
                return item.names[0]
            }
            if (let Some(name) <- find(item.members)) {
                return name
            }
        }
        None
    }
    find(itemTreeOf(db, id.file(db)).items) ?? throw FixtureException("no item ${wanted}")
}

let fileImportsReaderRuns = AtomicInt64(0)

/**
 * A query reading a file's imports, as a lookup will; it counts its runs.
 */
@CalcaTracked
func importedNameCount(db: AnalysisDatabase, pkg: Package, file: SourceFile): Int64 {
    fileImportsReaderRuns.fetchAdd(1)
    fileImports(db, pkg, file).names.size
}

@Test
class ScopeTest {
    @TestCase
    func aNameOfThePreludeIsFoundWithoutAnImport() {
        // N12
        checkScope(#"
            //- /std/core/core.cj module=std package=std.core
            package std.core
            public struct String {}
            public func println(x: String): Unit {}
            //          ^^^^^^^ def
            public enum Option<T> { | Some(T) | None }
            //- /main.cj module=m package=m
            package m
            func g() { $0println }
            "#)
    }

    @TestCase
    func anAliasOfANameOfThePreludeLeavesTheName() {
        // N12
        checkScope(#"
            //- /std/core/core.cj module=std package=std.core
            package std.core
            public struct String {}
            //            ^^^^^^ def
            public func println(x: String): Unit {}
            public enum Option<T> { | Some(T) | None }
            //- /main.cj module=m package=m
            package m
            import std.core.String as S
            func g(s: $0String) {}
            "#, ns: Namespace.Types)
    }

    @TestCase
    func aDeclarationOfThePackageShadowsAnImportedOne() {
        // N13, in another file of the package
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //- /main.cj module=m package=m
            package m
            import m.a.X
            func g() { $0X() }
            //- /x.cj module=m package=m
            package m
            class X {}
            //    ^ def
            "#)
    }

    @TestCase
    func aFunctionOfThePackageAndAnImportedOneAreOverloads() {
        // N14
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public func f(x: Bool) {}
            //          ^ def
            //- /main.cj module=m package=m
            package m
            import m.a.f
            func f(x: Int64) {}
            //   ^ def
            func g() { $0f(1) }
            "#)
    }

    @TestCase
    func twoGlobsBringingOneNameAreAmbiguous() {
        // N15
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //           ^ ambiguous
            //- /b/b.cj module=m package=m.b
            package m.b
            public class X {}
            //           ^ ambiguous
            //- /main.cj module=m package=m
            package m
            import m.a.*
            import m.b.*
            func g() { $0X() }
            "#)
    }

    @TestCase
    func anExplicitImportDoesNotWinOverAGlob() {
        // N16
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //           ^ ambiguous
            //- /b/b.cj module=m package=m.b
            package m.b
            public class X {}
            //           ^ ambiguous
            //- /main.cj module=m package=m
            package m
            import m.a.X
            import m.b.*
            func g() { $0X() }
            "#)
    }

    @TestCase
    func twoExplicitImportsOfOneNameAreAmbiguousAtTheUse() {
        // N17
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //           ^ ambiguous
            //- /b/b.cj module=m package=m.b
            package m.b
            public class X {}
            //           ^ ambiguous
            //- /main.cj module=m package=m
            package m
            import m.a.X
            import m.b.X
            func g() { $0X() }
            "#)
    }

    @TestCase
    func functionsOfTwoGlobsAreOverloads() {
        // N18
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public func f(x: Int64) {}
            //          ^ def
            //- /b/b.cj module=m package=m.b
            package m.b
            public func f(x: Bool) {}
            //          ^ def
            //- /main.cj module=m package=m
            package m
            import m.a.*
            import m.b.*
            func g() { $0f(1) }
            "#)
    }

    @TestCase
    func aGlobAndThePreludeBringingOneNameAreAmbiguous() {
        // N39: the prelude is an import of every name of std.core, at the level of the others
        checkScope(#"
            //- /std/core/core.cj module=std package=std.core
            package std.core
            public struct String {}
            //            ^^^^^^ ambiguous
            public func println(x: String): Unit {}
            public enum Option<T> { | Some(T) | None }
            //- /a/a.cj module=m package=m.a
            package m.a
            public class String {}
            //           ^^^^^^ ambiguous
            //- /main.cj module=m package=m
            package m
            import m.a.*
            func g() { $0String() }
            "#)
    }

    @TestCase
    func aReExportOfThePackageAndThePreludeBringingOneNameAreAmbiguous() {
        // N39, N11
        checkScope(#"
            //- /std/core/core.cj module=std package=std.core
            package std.core
            public struct String {}
            //            ^^^^^^ ambiguous
            public func println(x: String): Unit {}
            public enum Option<T> { | Some(T) | None }
            //- /a/a.cj module=m package=m.a
            package m.a
            public class String {}
            //           ^^^^^^ ambiguous
            //- /main.cj module=m package=m
            package m
            func g() { $0String() }
            //- /other.cj module=m package=m
            package m
            internal import m.a.String
            "#)
    }

    @TestCase
    func aPackageImportedUnderTheNameOfOneOfThePreludeIsAmbiguous() {
        // N39, N43
        checkScope(#"
            //- /std/core/core.cj module=std package=std.core
            package std.core
            public struct String {}
            //            ^^^^^^ ambiguous
            public func println(x: String): Unit {}
            public enum Option<T> { | Some(T) | None }
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /main.cj module=m package=m
            package m
            import m.a as String
            func g() { $0String.C() }
            //           ^^^^^^ ambiguous package m.a
            "#)
    }

    @TestCase
    func aFunctionOfThePackageShadowsAnImportedTypeAsAValue() {
        // N40
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class Foo {}
            //- /main.cj module=m package=m
            package m
            import m.a.Foo
            func Foo(x: Int64): Int64 { x }
            //   ^^^ def
            func g() { $0Foo(1) }
            "#)
    }

    @TestCase
    func aFunctionOfThePackageDoesNotShadowAnImportedTypeAsAType() {
        // N41
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class Foo {}
            //           ^^^ def
            //- /main.cj module=m package=m
            package m
            import m.a.Foo
            func Foo(x: Int64): Int64 { x }
            func g(v: $0Foo) {}
            "#, ns: Namespace.Types)
    }

    @TestCase
    func anImportedTypeAndAnImportedFunctionOfOneNameAreTheTypeAsAType() {
        // N41
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //           ^ def
            //- /b/b.cj module=m package=m.b
            package m.b
            public func X(x: Bool): Bool { x }
            //- /main.cj module=m package=m
            package m
            import m.a.X
            import m.b.X
            func g(v: $0X) {}
            "#, ns: Namespace.Types)
    }

    @TestCase
    func anImportedTypeAndAnImportedFunctionOfOneNameAreAmbiguousAsAValue() {
        // N42
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //           ^ ambiguous
            //- /b/b.cj module=m package=m.b
            package m.b
            public func X(x: Bool): Bool { x }
            //          ^ ambiguous
            //- /main.cj module=m package=m
            package m
            import m.a.X
            import m.b.*
            func g() { $0X(1) }
            "#)
    }

    @TestCase
    func aDeclarationOfThePackageShadowsAnImportedPackage() {
        // N43
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /main.cj module=m package=m
            package m
            import m.a
            class a {}
            //    ^ def
            func g() { $0a.C() }
            "#)
    }

    @TestCase
    func anImportedPackageAndAnImportedDeclarationOfOneNameAreAmbiguous() {
        // N43
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /b/b.cj module=m package=m.b
            package m.b
            public class a {}
            //           ^ ambiguous
            //- /main.cj module=m package=m
            package m
            import m.a
            import m.b.a
            func g() { $0a.C() }
            //         ^ ambiguous package m.a
            "#)
    }

    @TestCase
    func theConstructorsOfAnEnumComeWithItUnderAnAlias() {
        // N44
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public enum Color { | Red | Green }
            //                    ^^^ imported ctor
            //- /main.cj module=m package=m
            package m
            import m.a.Color as K
            func g() { $0Red }
            "#)
    }

    @TestCase
    func theConstructorsOfAnEnumComeWithAGlob() {
        // N44
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public enum Color { | Red | Green }
            //                    ^^^ imported ctor
            //- /main.cj module=m package=m
            package m
            import m.a.*
            func g() { $0Red }
            "#)
    }

    @TestCase
    func theConstructorsOfAnEnumComeWithItsReExport() {
        // N44
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public enum Color { | Red | Green }
            //                    ^^^ imported ctor
            //- /b/b.cj module=m package=m.b
            package m.b
            public import m.a.Color
            //- /main.cj module=m package=m
            package m
            import m.b.Color
            func g() { $0Red }
            "#)
    }

    @TestCase
    func anImportedPackageBringsNoConstructors() {
        // N44
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public enum Color { | Red | Green }
            //- /main.cj module=m package=m
            package m
            import m.a
            func g() { $0Red }
            //           ^^^ not found
            "#)
    }

    @TestCase
    func anImportedTypeWinsOverAConstructorOfThePackage() {
        // N45
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class Red {}
            //           ^^^ def
            //- /main.cj module=m package=m
            package m
            import m.a.Red
            enum Color { | Red | Green }
            func g() { let c: Color = $0Red }
            "#)
    }

    @TestCase
    func constructorsOfThePackageAndImportedOnesAreAllCandidates() {
        // N46: the expected type chooses among them
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public enum Color { | Red | Green }
            //                    ^^^ imported ctor
            //- /main.cj module=m package=m
            package m
            import m.a.Color
            enum Light { | Red | Off }
            //             ^^^ ctor
            func g() { $0Red }
            "#)
    }

    @TestCase
    func constructorsOfAGlobAndOfThePreludeAreAllCandidates() {
        // N46
        checkScope(#"
            //- /std/core/core.cj module=std package=std.core
            package std.core
            public struct String {}
            public func println(x: String): Unit {}
            public enum Option<T> { | Some(T) | None }
            //                                  ^^^^ imported ctor
            //- /a/a.cj module=m package=m.a
            package m.a
            public enum Opt { | None | Here }
            //                  ^^^^ imported ctor
            //- /main.cj module=m package=m
            package m
            import m.a.*
            func g() { $0None }
            "#)
    }

    @TestCase
    func aConstructorIsNoType() {
        // N41
        checkScope(#"
            //- /main.cj module=m package=m
            package m
            enum Color { | Red | Green }
            func g(c: $0Red) {}
            //          ^^^ not found
            "#, ns: Namespace.Types)
    }

    @TestCase
    func aPrivateDeclarationOfAnotherFileDoesNotShadowAnImport() {
        // N49
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //           ^ def
            //- /main.cj module=m package=m
            package m
            import m.a.X
            func g() { $0X() }
            //- /other.cj module=m package=m
            package m
            private class X {}
            "#)
    }

    @TestCase
    func aPlainImportOfTheFileAndAReExportOfThePackageAreAmbiguous() {
        // N11
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //           ^ ambiguous
            //- /b/b.cj module=m package=m.b
            package m.b
            public class X {}
            //           ^ ambiguous
            //- /main.cj module=m package=m
            package m
            import m.a.X
            func g() { $0X() }
            //- /other.cj module=m package=m
            package m
            internal import m.b.X
            "#)
    }

    @TestCase
    func aPlainImportOfAnotherFileIsNotSeen() {
        // N11
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //- /main.cj module=m package=m
            package m
            func g() { $0X() }
            //         ^ not found
            //- /other.cj module=m package=m
            package m
            import m.a.X
            "#)
    }

    @TestCase
    func oneDeclarationImportedTwiceIsOne() {
        // N34, N48
        checkScope(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //           ^ def
            //- /main.cj module=m package=m
            package m
            import m.a.X
            import m.a.*
            func g() { $0X() }
            "#)
    }

    @TestCase
    func aNameAddedToAGlobbedPackageLeavesTheFileImportsAlone() {
        // arrange
        let parsed = Fixture.parse(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //- /main.cj module=m package=m
            package m
            import m.a.*
            "#)
        let db = parsed.database()
        let mainFile = parsed.files[1]
        let source = db.sourceFile(mainFile.fileId).getOrThrow()
        let pkg = sourcePackageOf(db, mainFile)
        importedNameCount(db, pkg, source)
        let before = fileImportsReaderRuns.load()
        // act
        db.setFileText(parsed.files[0].fileId, Rope("package m.a\npublic class X {}\npublic class Y {}\n"))
        importedNameCount(db, pkg, source)
        // assert
        @Expect(fileImportsReaderRuns.load(), before)
        @Expect(lookUp(db, pkg, source, "Y", Namespace.Values) == Resolution.NotFound, false)
    }
}
