package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*
import loupe.syntax.parse

/**
 * Checks where the name at the cursor of `fixture` is declared is its annotations, as `checkDefinition`, with the
 * `.cjo`s of std.core and of std.unittest's packages among its packages.
 */
func checkDefinitionWithUnittest(fixture: String): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database(binaries: ["std.core", "std.unittest", "std.unittest.common", "std.unittest.testmacro"].map {
        name => stdCjoRead(name, stdCjo(name))
    })
    let cursor = parsed.cursor ?? throw FixtureException("no $0 in the fixture")
    let targets = definitionAt(db, cursor.fileId, cursor.offset)
    let annotations = if (targets.isEmpty()) {
        let source = db.sourceFile(cursor.fileId).getOrThrow()
        let token = tokenAt(parse(db, source).syntaxNode(), cursor.offset) ?? throw FixtureException("no name at $0")
        [Annotation(cursor.fileId, token.textRange, "no definition")]
    } else {
        targets.map {
            target =>
            @Expect(target.fullRange.start <= target.focusRange.start && target.focusRange.end <= target.fullRange.end)
            Annotation(target.fileId, target.focusRange, "def")
        }
    }
    expectAnnotations(fixture, annotations)
}

/**
 * What std.unittest's macros declare (#175) is declared where the call is: a test class's members at the macro, an
 * option's key at the option's name, a strategy at its function's name.
 */
@Test
class UnittestDefinitionTest {
    @TestCase
    func aMemberOfATestClassGoesToTest() {
        checkDefinitionWithUnittest(#"
            //- /main.cj module=m package=m
              package m
              import std.unittest.*
              import std.unittest.testmacro.*
              @Test
            // ^^^^ def
              class C {}
              func f(c: C): TestSuite {
                  c.$0asTestSuite()
              }
            "#)
    }

    @TestCase
    func theTestClassOfATestFunctionGoesToTest() {
        checkDefinitionWithUnittest(#"
            //- /main.cj module=m package=m
              package m
              import std.unittest.*
              import std.unittest.testmacro.*
              @Test
            // ^^^^ def
              func g(): Unit {}
              func f(): Unit {
                  $0TestCase_g()
              }
            "#)
    }

    @TestCase
    func theKeyOfAnOptionGoesToItsName() {
        checkDefinitionWithUnittest(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @UnittestOption[Int64](public zxc, "an option")
            //                            ^^^ def
            func f(): Unit {
                let key = KeyZxc.$0zxc
            }
            "#)
    }

    @TestCase
    func aStrategyGoesToItsFunctionsName() {
        checkDefinitionWithUnittest(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Strategy[x in [1, 2]]
            func strat(x: Int64): Int64 { x }
            //   ^^^^^ def
            func f(): Unit {
                let s = $0strat
            }
            "#)
    }
}
