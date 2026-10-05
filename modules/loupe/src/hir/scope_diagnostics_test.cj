package loupe.hir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange
import cjsyntax.ast.{ImportDecl, ImportTree}
import loupe.db.AnalysisDatabase
import loupe.fixture.*
import loupe.syntax.parse

/**
 * The range of the path `site` names, from its first token to its last.
 */
func rangeOf(db: AnalysisDatabase, site: ImportSite): TextRange {
    match (site.file) {
        case ItemFile.Source(file) =>
            let root = parse(db, file).syntaxNode()
            let decl = ImportDecl.cast(itemIdMap(db, file).node(site.item, root).getOrThrow()).getOrThrow()
            let leaves = ArrayList<ImportTree>()
            leavesOf(decl.importTree().getOrThrow(), leaves)
            tightRange(leaves[site.path].syntax)
        case ItemFile.Binary(_, _) => throw FixtureException("an import of a .cjo")
    }
}

/**
 * Checks the `scopeDiagnostics` of every file of `fixture` are its annotations: `//^ error: …` or
 * `//^ warning: …` under the path of an import, or under the name of a declaration.
 */
func checkScopeDiagnostics(fixture: String): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database()
    let actual = ArrayList<Annotation>()
    for (file in parsed.files) {
        let source = db.sourceFile(file.fileId).getOrThrow()
        for (diagnostic in scopeDiagnostics(db, sourcePackageOf(db, file), source)) {
            actual.add(match (diagnostic.at) {
                case AtImport(site) => Annotation(file.fileId, rangeOf(db, site), diagnostic.problem.toString())
                case AtDecl(def, name) => annotationOn(db, def, name, diagnostic.problem.toString())
            })
        }
    }
    expectAnnotations(fixture, actual.toArray())
}

@Test
class ScopeDiagnosticsTest {
    @TestCase
    func aNameThePackageDoesNotHaveIsAnError() {
        // N35
        checkScopeDiagnostics(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            class Hidden {}
            //- /main.cj module=m package=m
            package m
            import m.a.Hidden
            //     ^^^^^^^^^^ error: 'Hidden' is not accessible in package 'm.a'
            "#)
    }

    @TestCase
    func aPackageImportingItselfIsAnError() {
        // N47
        checkScopeDiagnostics(#"
            //- /main.cj module=m package=m
            package m
            import m.*
            //     ^^^ error: package 'm' should not import itself
            "#)
    }

    @TestCase
    func aTypeOfThePackageShadowingAnImportWarns() {
        // N13, N40
        checkScopeDiagnostics(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public func Foo(x: Bool): Bool { x }
            //- /main.cj module=m package=m
            package m
            import m.a.Foo
            //     ^^^^^^^ warning: imported decl 'Foo' is shadowed
            class Foo {}
            "#)
    }

    @TestCase
    func aFunctionOfThePackageShadowingAnImportedTypeDoesNotWarn() {
        // N40
        checkScopeDiagnostics(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class Foo {}
            //- /main.cj module=m package=m
            package m
            import m.a.Foo
            func Foo(x: Int64): Int64 { x }
            "#)
    }

    @TestCase
    func aPrivateDeclarationOfAnotherFileDoesNotShadowAnImport() {
        // N49: cjc warns, wrongly
        checkScopeDiagnostics(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //- /main.cj module=m package=m
            package m
            import m.a.X
            //- /other.cj module=m package=m
            package m
            private class X {}
            "#)
    }

    @TestCase
    func twoPathsImportingOneNameWarn() {
        // N17, N48: functions too, though they overload at the use
        checkScopeDiagnostics(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public func f(x: Int64): Int64 { x }
            //- /b/b.cj module=m package=m.b
            package m.b
            public func f(x: Bool): Bool { x }
            //- /main.cj module=m package=m
            package m
            import m.a.f
            import m.b.f
            //     ^^^^^ warning: imported decl 'f' is conflicted with other import
            "#)
    }

    @TestCase
    func aPackageAndADeclarationImportedUnderOneNameWarn() {
        // N43
        checkScopeDiagnostics(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /b/b.cj module=m package=m.b
            package m.b
            public class a {}
            //- /main.cj module=m package=m
            package m
            import m.a
            import m.b.a
            //     ^^^^^ warning: imported decl 'a' is conflicted with other import
            "#)
    }

    @TestCase
    func packagesImportingEachOtherAreACycle() {
        // N36
        checkScopeDiagnostics(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            import m.b.*
            //     ^^^^^ error: cyclic dependency through 'm.b'
            //- /b/b.cj module=m package=m.b
            package m.b
            import m.a.*
            //     ^^^^^ error: cyclic dependency through 'm.a'
            //- /main.cj module=m package=m
            package m
            import m.a.*
            "#)
    }

    @TestCase
    func aDeclarationNamedLikeASubPackageIsAnError() {
        // N30
        checkScopeDiagnostics(#"
            //- /p/p.cj module=m package=m.p
            package m.p
            public func q(): Int64 { 1 }
            //          ^ error: top-level declaration 'q' is conflicted with possible sub-package 'm.p.q'
            //- /p/q/q.cj module=m package=m.p.q
            package m.p.q
            public func f(): Int64 { 2 }
            "#)
    }

    @TestCase
    func aGlobBringingNothingIsNoError() {
        // N50
        checkScopeDiagnostics(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            class Hidden {}
            //- /main.cj module=m package=m
            package m
            import m.a.*
            "#)
    }
}
