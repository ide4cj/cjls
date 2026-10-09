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
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.fixture.*
import loupe.syntax.parse
import loupe.vfs.FileId

/**
 * The package a file of a fixture is in.
 */
func packageOf(db: AnalysisDatabase, file: FixtureFile): PackageRef {
    for (module in db.project().getOrThrow().modules(db) where module.name(db) == file.module) {
        for (pkg in module.packages(db) where pkg.name(db) == file.pkg) {
            return PackageRef.Source(pkg)
        }
    }
    throw FixtureException("no package ${file.pkg} in module ${file.module}")
}

/**
 * An annotation of `text` on `name` in the declaration of `def`: its first token of that text.
 */
func annotationOn(db: AnalysisDatabase, def: DefId, name: String, text: String): Annotation {
    match (def.file(db)) {
        case ItemFile.Source(file) =>
            let root = parse(db, file).syntaxNode()
            let node = itemIdMap(db, file).node(def.item(db), root).getOrThrow()
            for (element in node.descendantsWithTokens()) {
                if (let SyntaxElement.Token(token) <- element) {
                    if (identText(token) == name) {
                        return Annotation(file.fileId(db), token.textRange, text)
                    }
                }
            }
            throw FixtureException("no ${name} in the declaration of ${def}")
        case ItemFile.Binary(_, _) => throw FixtureException("${def} is of a .cjo, which a fixture has none of")
        case ItemFile.Expansion(_) => throw FixtureException("${def} is of an expansion, which a def map has none of")
    }
}

/**
 * Checks the `defMap` of every package of `fixture` is its annotations, under the names of the
 * declarations: `//^ internal` a declaration and its visibility, `//^ ctor public` an enum's
 * constructor, `//^ error: redefinition of 'A'` a redefinition.
 */
func checkDefMap(fixture: String): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database()
    let seen = ArrayList<PackageRef>()
    let actual = ArrayList<Annotation>()
    for (file in parsed.files) {
        let pkg = packageOf(db, file)
        if (seen.contains(pkg)) {
            continue
        }
        seen.add(pkg)
        let map = defMap(db, pkg)
        for ((name, defs) in map.names) {
            actual.add(all: defs.map {def => annotationOn(db, def.id, name, "${def.visibility}")})
        }
        for ((name, defs) in map.ctors) {
            actual.add(all: defs.map {def => annotationOn(db, def.id, name, "ctor ${def.visibility}")})
        }
        actual.add(all: map.errors.map {
            error => annotationOn(db, error.def, error.name, "error: redefinition of '${error.name}'")
        })
    }
    expectAnnotations(fixture, actual.toArray())
}

/**
 * Checks what the name at the cursor of `fixture` stands for among its package's declarations, as
 * seen from its file, is its annotations: `//^ def` under each.
 */
func checkLookUp(fixture: String): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database()
    let cursor = parsed.cursor ?? throw FixtureException("no $0 in the fixture")
    let file = parsed.files.iterator().filter {file => file.fileId == cursor.fileId}.next().getOrThrow()
    let source = db.sourceFile(file.fileId).getOrThrow()
    var name: ?String = None
    for (element in parse(db, source).syntaxNode().descendantsWithTokens()) {
        if (let SyntaxElement.Token(token) <- element) {
            if (token.textRange.start <= cursor.offset && cursor.offset < token.textRange.end) {
                name = identText(token)
            }
        }
    }
    let wanted = name ?? throw FixtureException("no token at $0")
    let found = defMap(db, packageOf(db, file)).lookUp(db, wanted, from: ItemFile.Source(source))
    expectAnnotations(fixture, found.map {def => annotationOn(db, def, wanted, "def")})
}

let defMapReaderRuns = AtomicInt64(0)

/**
 * A query reading the def map, as resolution will; it counts its runs.
 */
@CalcaTracked
func defMapNames(db: AnalysisDatabase, pkg: PackageRef): Array<String> {
    defMapReaderRuns.fetchAdd(1)
    defMap(db, pkg).names.keys().toArray()
}

@Test
class DefMapTest {
    @TestCase
    func aPackagesDeclarationsAreItsNamesWithTheirVisibilityAndNotTheirMembers() {
        checkDefMap(#"
            class A {
            //    ^ internal
                func m() {}
            }
            public func f() {}
            //          ^ public
            private let v = 1
            //          ^ private
            protected struct S {}
            //               ^ protected
            let (x, y) = (1, 2)
            //   ^ internal
            //      ^ internal
            extend A {}
            "#)
    }

    @TestCase
    func overloadsInSeveralFilesAreOneName() {
        // N21
        checkDefMap(#"
            //- /a.cj
            func f(x: Int64) {}
            //   ^ internal
            //- /b.cj
            func f(x: String) {}
            //   ^ internal
            "#)
    }

    @TestCase
    func aNameTakenByAnythingButAFunctionIsRedefinedByEveryLaterDeclaration() {
        // N19, N20
        checkDefMap(#"
            //- /a.cj
            class A {}
            //    ^ internal
            func A() {}
            //   ^ error: redefinition of 'A'
            //   ^ internal
            let v = 1
            //  ^ internal
            func v() {}
            //   ^ error: redefinition of 'v'
            //   ^ internal
            type T = Int64
            //   ^ internal
            //- /b.cj
            class T {}
            //    ^ error: redefinition of 'T'
            //    ^ internal
            "#)
    }

    @TestCase
    func aPrivateDeclarationTakesItsNameInThePackageAndOverloadsOthers() {
        // N22, N23
        checkDefMap(#"
            //- /a.cj
            private class P {}
            //            ^ private
            private func g(x: Int64) {}
            //           ^ private
            //- /b.cj
            class P {}
            //    ^ error: redefinition of 'P'
            //    ^ internal
            func g(x: String) {}
            //   ^ internal
            "#)
    }

    @TestCase
    func anEnumsConstructorsAreALevelOfTheirOwnWithTheEnumsVisibility() {
        // N24, N27
        checkDefMap(#"
            enum Color { | Red | Green }
            //   ^^^^^ internal
            //             ^^^ ctor internal
            //                   ^^^^^ ctor internal
            func Red() {}
            //   ^^^ internal
            enum E { | E }
            //   ^ internal
            //         ^ ctor internal
            public enum Pub { | One }
            //          ^^^ public
            //                  ^^^ ctor public
            "#)
    }

    @TestCase
    func aPrivateDeclarationIsSeenInItsFile() {
        // N1
        checkLookUp(#"
            //- /a.cj
            private func p() {}
            //           ^ def
            func useHere() { $0p() }
            "#)
    }

    @TestCase
    func aPrivateDeclarationIsNotSeenInAnotherFileOfItsPackage() {
        // N1
        checkLookUp(#"
            //- /a.cj
            private func p() {}
            //- /b.cj
            func useOther() { $0p() }
            "#)
    }

    @TestCase
    func overloadsSeenFromAnotherFileLeaveOutThePrivateOnes() {
        // N23
        checkLookUp(#"
            //- /a.cj
            private func g(x: Int64) {}
            func g(x: Bool) {}
            //   ^ def
            //- /b.cj
            func g(x: String) {}
            //   ^ def
            func use() { $0g("s") }
            "#)
    }

    @TestCase
    func aDeclarationHidesTheConstructorsOfItsName() {
        // N25
        checkLookUp(#"
            enum Color { | Red | Green }
            func Red() {}
            //   ^^^ def
            func use() { R$0ed() }
            "#)
    }

    @TestCase
    func aConstructorIsFoundWhenNoDeclarationHasItsName() {
        checkLookUp(#"
            enum Color { | Red | Green }
            //                   ^^^^^ def
            func use() { Gr$0een }
            "#)
    }

    @TestCase
    func theConstructorsOfTwoEnumsAreBothFoundForTheUseToTellApart() {
        // N26
        checkLookUp(#"
            enum C1 { | Same }
            //          ^^^^ def
            enum C2 { | Same }
            //          ^^^^ def
            func use() { Sa$0me }
            "#)
    }

    @TestCase
    func anEditInsideABodyLeavesTheDefMapAndWhatReadItAlone() {
        // arrange
        let parsed = Fixture.parse("func f() {\n    1\n}\nclass C {}\n")
        let db = parsed.database()
        let pkg = packageOf(db, parsed.files[0])
        let names = defMapNames(db, pkg)
        let runs = defMapReaderRuns.load()

        // act
        db.setFileText(parsed.files[0].fileId, Rope("func f() {\n    let x = 1 + 2\n    x\n}\nclass C {}\n"))
        let again = defMapNames(db, pkg)

        // assert
        @Expect(again, names)
        @Expect(defMapReaderRuns.load(), runs)
    }
}
