package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*
import loupe.syntax.parse

/**
 * Checks where the name at the cursor of `fixture` is declared is its annotations, as `checkDefinition`, with std.core's
 * and std.deriving's `.cjo`s among its packages.
 */
func checkDefinitionWithDerive(fixture: String): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core")),
        stdCjoRead("std.deriving", stdCjo("std.deriving"))])
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
 * A member `@Derive` adds (#175) is declared where the call names its interface.
 */
@Test
class DeriveDefinitionTest {
    @TestCase
    func aDerivedMemberAfterADotGoesToItsInterfaceInTheCall() {
        checkDefinitionWithDerive(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[ToString, Hashable]
            //                ^^^^^^^^ def
            struct S {}
            func f(s: S): Int64 {
                s.$0hashCode()
            }
            "#)
    }

    @TestCase
    func aDerivedOperatorGoesToItsInterfaceInTheCall() {
        checkDefinitionWithDerive(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Equatable]
            //      ^^^^^^^^^ def
            class P<T> {
                P(let x: T) {}
            }
            func f(a: P<Int64>, b: P<Int64>): Bool {
                a $0== b
            }
            "#)
    }

    @TestCase
    func theEquatableComparableAddsGoesToComparable() {
        checkDefinitionWithDerive(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Hashable]
            @Derive[Comparable where T <: Comparable<T>]
            //      ^^^^^^^^^^ def
            struct R<T> {}
            func f(a: R<Int64>, b: R<Int64>): Bool {
                a $0!= b
            }
            "#)
    }

    @TestCase
    func aDerivedMemberOfAnotherFileOfThePackage() {
        checkDefinitionWithDerive(#"
            //- /a.cj module=m package=m
            package m
            import std.deriving.Derive
            @Derive[Hashable]
            //      ^^^^^^^^ def
            public struct S {}
            //- /b.cj module=m package=m
            package m
            func f(s: S): Int64 {
                s.$0hashCode()
            }
            "#)
    }
}
