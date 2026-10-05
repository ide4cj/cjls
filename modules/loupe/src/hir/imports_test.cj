package loupe.hir

import std.collection.*
import std.sync.AtomicInt64
import std.unittest.*
import std.unittest.testmacro.*
import calca.*
import calca.macros.*
import ginkgo.{SyntaxElement, TextRange}
import cjsyntax.CjSyntaxNode
import cjsyntax.ast.{ImportDecl, ImportTree}
import rope.Rope
import loupe.db.AnalysisDatabase
import loupe.fixture.*
import loupe.syntax.parse
import loupe.vfs.FileId

/**
 * The leaves of `tree`, in the order `ItemTree` lowers them to paths.
 */
func leavesOf(tree: ImportTree, leaves: ArrayList<ImportTree>): Unit {
    match (tree.importTreeList()) {
        case Some(list) => for (inner in list.importTrees()) {
            leavesOf(inner, leaves)
        }
        case None => leaves.add(tree)
    }
}

/**
 * The range of `node` from its first token to its last, whitespace and comments left out.
 */
func tightRange(node: CjSyntaxNode): TextRange {
    var range: ?TextRange = None
    for (element in node.descendantsWithTokens()) {
        if (let SyntaxElement.Token(token) <- element && !token.kind.isTrivia()) {
            range = match (range) {
                case Some(r) => TextRange(r.start, token.textRange.end)
                case None => token.textRange
            }
        }
    }
    range.getOrThrow()
}

/**
 * The name `def` is declared by, its first.
 */
func declaredName(db: AnalysisDatabase, def: DefId): String {
    let tree = itemTreeOf(db, def.file(db))
    tree.items.iterator().filter {item => item.id == def.item(db)}.next().getOrThrow().names[0]
}

/**
 * Checks what the path of an import at the cursor of `fixture` brings is its annotations: `//^ def`
 * under each declaration it brings by its own name, `//^ def as Y` under one it brings as `Y`;
 * `//^ package p as a` or `//^ error: …` under the path.
 */
func checkImport(fixture: String): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database()
    let cursor = parsed.cursor ?? throw FixtureException("no $0 in the fixture")
    let file = parsed.files.iterator().filter {file => file.fileId == cursor.fileId}.next().getOrThrow()
    let source = db.sourceFile(file.fileId).getOrThrow()
    let root = parse(db, source).syntaxNode()
    let ids = itemIdMap(db, source)
    for (item in itemTree(db, source).imports) {
        let decl = ImportDecl.cast(ids.node(item.id, root).getOrThrow()).getOrThrow()
        let leaves = ArrayList<ImportTree>()
        leavesOf(decl.importTree().getOrThrow(), leaves)
        for ((leaf, path) in leaves.iterator().zip(item.paths.iterator())) {
            let range = tightRange(leaf.syntax)
            if (cursor.offset < range.start || range.end < cursor.offset) {
                continue
            }
            let annotations = match (resolveImport(db, packageOf(db, file), path, importLevelOf(item))) {
                case ToPackage(name, pkg) => [Annotation(file.fileId, range, "package ${nameOf(db, pkg)} as ${name}")]
                case ToNames(_, names) =>
                    let found = ArrayList<Annotation>()
                    for ((name, defs) in names) {
                        for (def in defs) {
                            let own = declaredName(db, def)
                            let text = if (own == name) {
                                "def"
                            } else {
                                "def as ${name}"
                            }
                            found.add(annotationOn(db, def, own, text))
                        }
                    }
                    found.toArray()
                case Unresolved(error) => [Annotation(file.fileId, range, "error: ${error}")]
            }
            expectAnnotations(fixture, annotations)
            return
        }
    }
    throw FixtureException("no path of an import at $0")
}

let exportsReaderRuns = AtomicInt64(0)

/**
 * A query reading a package's exports, as a file's scope will; it counts its runs.
 */
@CalcaTracked
func exportedNames(db: AnalysisDatabase, pkg: PackageRef): Array<String> {
    exportsReaderRuns.fetchAdd(1)
    packageExports(db, pkg).names.keys().toArray()
}

@Test
class ImportsTest {
    @TestCase
    func aNameImportedBringsEveryOverloadOfIt() {
        // N5
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public func f(x: Int64) {}
            //          ^ def
            public func f(x: Bool) {}
            //          ^ def
            //- /main.cj module=m package=m
            package m
            import m.a.$0f
            "#)
    }

    @TestCase
    func aNameImportedUnderAnAliasIsBroughtAsTheAlias() {
        // N6
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //           ^ def as D
            //- /main.cj module=m package=m
            package m
            import m.a.C as $0D
            "#)
    }

    @TestCase
    func aPathNamingAPackageBringsThePackageUnderItsLastSegment() {
        // N7
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /main.cj module=m package=m
            package m
            import m.$0a
            //     ^^^ package m.a as a
            "#)
    }

    @TestCase
    func aPackageImportedUnderAnAliasIsBroughtAsTheAlias() {
        // N8
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /main.cj module=m package=m
            package m
            import m.$0a as z
            //     ^^^^^^^^^^ package m.a as z
            "#)
    }

    @TestCase
    func aGlobFromAnotherPackageOfTheModuleBringsItsPublicAndProtectedDeclarations() {
        // N10, N2, N3: m is m.a's parent, not its child, so m.a's internal ones are not seen
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class Pub {}
            //           ^^^ def
            protected class Prot {}
            //              ^^^^ def
            class Int {}
            private class Priv {}
            //- /main.cj module=m package=m
            package m
            import m.a.$0*
            "#)
    }

    @TestCase
    func aGlobFromAPackageUnderTheImportedOneBringsItsInternalDeclarations() {
        // N2
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            class Int {}
            //    ^^^ def
            private class Priv {}
            //- /a/b/b.cj module=m package=m.a.b
            package m.a.b
            import m.a.$0*
            "#)
    }

    @TestCase
    func aGlobFromAnotherModuleBringsThePublicDeclarationsAlone() {
        // N3, N4
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class Pub {}
            //           ^^^ def
            protected class Prot {}
            //- /main.cj module=n package=n deps=m
            package n
            import m.a.$0*
            "#)
    }

    @TestCase
    func aPackageOfAModuleNotAmongTheDepsIsNotFound() {
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //- /main.cj module=n package=n
            package n
            import m.a.$0X
            //     ^^^^^ error: can not find package 'm.a'
            "#)
    }

    @TestCase
    func anImportOfAPackageThatIsNotIsAnError() {
        checkImport(#"
            //- /main.cj module=m package=m
            package m
            import m.zz.$0*
            //     ^^^^^^ error: can not find package 'm.zz'
            "#)
    }

    @TestCase
    func aNameThePackageDoesNotDeclareIsAnErrorAtTheImport() {
        // N35
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //- /main.cj module=m package=m
            package m
            import m.a.$0Nope
            //     ^^^^^^^^^^ error: 'Nope' is not accessible in package 'm.a'
            "#)
    }

    @TestCase
    func aConstructorIsNotImportedByItsName() {
        // N38: it comes with its enum
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public enum Color { | Red | Green }
            //- /main.cj module=m package=m
            package m
            import m.a.$0Red
            //     ^^^^^^^^^ error: 'Red' is not accessible in package 'm.a'
            "#)
    }

    @TestCase
    func aPlainImportIsNotExported() {
        // N11
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //- /b/b.cj module=m package=m.b
            package m.b
            import m.a.X
            //- /main.cj module=m package=m
            package m
            import m.b.$0X
            //     ^^^^^ error: 'X' is not accessible in package 'm.b'
            "#)
    }

    @TestCase
    func anInternalReExportIsSeenByAPackageUnderTheReExportingOne() {
        // N11
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //           ^ def
            //- /b/b.cj module=m package=m.b
            package m.b
            internal import m.a.X
            //- /b/c/c.cj module=m package=m.b.c
            package m.b.c
            import m.b.$0X
            "#)
    }

    @TestCase
    func anInternalReExportIsNotSeenByASiblingPackage() {
        // N11
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //- /b/b.cj module=m package=m.b
            package m.b
            internal import m.a.X
            //- /d/d.cj module=m package=m.d
            package m.d
            import m.b.$0X
            //     ^^^^^ error: 'X' is not accessible in package 'm.b'
            "#)
    }

    @TestCase
    func aReExportOfADeclarationNarrowerThanItBringsNothing() {
        // N37: `public import` of an internal X leaves it out, even in m.a.b itself, silently
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            class X {}
            //- /a/b/b.cj module=m package=m.a.b
            package m.a.b
            public import m.a.$0X
            "#)
    }

    @TestCase
    func reExportsChainAcrossPackages() {
        // N28
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //           ^ def
            //- /b/b.cj module=m package=m.b
            package m.b
            public import m.a.X
            //- /c/c.cj module=m package=m.c
            package m.c
            public import m.b.X
            //- /main.cj module=m package=m
            package m
            import m.c.$0X
            "#)
    }

    @TestCase
    func aGlobBringsWhatThePackageReExports() {
        // N29
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //           ^ def
            //- /b/b.cj module=m package=m.b
            package m.b
            public import m.a.*
            public class Y {}
            //           ^ def
            //- /main.cj module=m package=m
            package m
            import m.b.$0*
            "#)
    }

    @TestCase
    func aPathIsAPackageBeforeItIsADeclaration() {
        // N30
        checkImport(#"
            //- /p/p.cj module=m package=m.p
            package m.p
            public func q(): Int64 { 1 }
            //- /p/q/q.cj module=m package=m.p.q
            package m.p.q
            public func f(): Int64 { 2 }
            //- /main.cj module=m package=m
            package m
            import m.p.$0q
            //     ^^^^^ package m.p.q as q
            "#)
    }

    @TestCase
    func aPackageIsNotReExported() {
        // N31
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //- /b/b.cj module=m package=m.b
            package m.b
            public import m.$0a
            //            ^^^ error: imported package name 'm.a' cannot be re-exported
            "#)
    }

    @TestCase
    func aReExportUnderAnAliasExportsTheAlias() {
        // N32
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //           ^ def as Y
            //- /b/b.cj module=m package=m.b
            package m.b
            public import m.a.X as Y
            //- /main.cj module=m package=m
            package m
            import m.b.$0Y
            "#)
    }

    @TestCase
    func aReExportUnderAnAliasDoesNotExportTheOriginalName() {
        // N32
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //- /b/b.cj module=m package=m.b
            package m.b
            public import m.a.X as Y
            //- /main.cj module=m package=m
            package m
            import m.b.$0X
            //     ^^^^^ error: 'X' is not accessible in package 'm.b'
            "#)
    }

    @TestCase
    func aPackageExportsItsOwnDeclarationAndTheOneItReExportsOfOneName() {
        // N33: within m.b its own X shadows the import; its importers get both, an ambiguity at the use
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //           ^ def
            //- /b/b.cj module=m package=m.b
            package m.b
            public import m.a.X
            public class X {}
            //           ^ def
            //- /main.cj module=m package=m
            package m
            import m.b.$0X
            "#)
    }

    @TestCase
    func aDeclarationReExportedTwiceIsExportedOnce() {
        // N34
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class X {}
            //           ^ def
            //- /b/b.cj module=m package=m.b
            package m.b
            public import m.a.X
            public import m.a.*
            //- /main.cj module=m package=m
            package m
            import m.b.$0X
            "#)
    }

    @TestCase
    func aPackageImportingItselfIsAnError() {
        // N47
        checkImport(#"
            //- /b/b.cj module=m package=m.b
            package m.b
            public import m.b.$0*
            //            ^^^^^ error: package 'm.b' should not import itself
            public class X {}
            "#)
    }

    @TestCase
    func packagesReExportingEachOtherAreACycle() {
        // N36
        checkImport(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public import m.b.*
            public class X {}
            //- /b/b.cj module=m package=m.b
            package m.b
            public import m.a.*
            //- /main.cj module=m package=m
            package m
            import m.a.$0X
            //     ^^^^^ error: cyclic dependency through 'm.a'
            "#)
    }

    @TestCase
    func aDeclarationAddedToAPackageLeavesTheExportsOfOneReExportingAnotherNameAlone() {
        // arrange
        let parsed = Fixture.parse(#"
            //- /a/a.cj module=m package=m.a
            public class X {}
            //- /b/b.cj module=m package=m.b
            public import m.a.X
            "#)
        let db = parsed.database()
        let b = packageOf(db, parsed.files[1])
        let names = exportedNames(db, b)
        let runs = exportsReaderRuns.load()

        // act
        db.setFileText(parsed.files[0].fileId, Rope("public class X {}\npublic class Z {}\n"))
        let again = exportedNames(db, b)

        // assert
        @Expect(again, names)
        @Expect(exportsReaderRuns.load(), runs)
    }
}
