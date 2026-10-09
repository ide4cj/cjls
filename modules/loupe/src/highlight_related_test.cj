package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*

/**
 * Checks the names `highlightRelated` finds at the `$0` of `fixture` are its annotations, each
 * labeled with how it reaches what it means, `text` for neither.
 */
func checkHighlightRelated(fixture: String): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database()
    let cursor = parsed.cursor ?? throw FixtureException("no $0 in the fixture")
    let found = highlightRelated(db, cursor.fileId, cursor.offset).map {
        one => Annotation(cursor.fileId, one.range, one.access.map {access => access.toString()} ?? "text")
    }
    expectAnnotations(fixture, found)
}

@Test
class HighlightRelatedTest {
    @TestCase
    func aLocalShadowedInAnInnerScopeHighlightsOnlyItsOwnUses() {
        checkHighlightRelated(#"
            //- /main.cj module=m package=m
            package m
            func f(x: Int64): Int64 {
                if (true) {
                    let x = 2
            //          ^ text
                    return $0x + x
            //               ^ read
            //                   ^ read
                }
                x
            }
            "#)
    }

    @TestCase
    func aFieldWrittenThroughThisIsWritten() {
        checkHighlightRelated(#"
            //- /main.cj module=m package=m
            package m
            class C {
                var x = 0
            //      ^ write
                func set(v: Int64): Unit {
                    this.x = v
            //           ^ write
                }
                func get(): Int64 {
                    $0x
            //        ^ read
                }
            }
            "#)
    }

    @TestCase
    func aMemberReachedThroughAValueOfAnotherTypeIsNotHighlighted() {
        checkHighlightRelated(#"
            //- /main.cj module=m package=m
            package m
            class A {
                var n = 0
            //      ^ write
            }
            class B {
                var n = 0
            }
            func f(a: A, b: B): Int64 {
                a.$0n + b.n + a.n
            //      ^ read
            //                  ^ read
            }
            "#)
    }

    @TestCase
    func compoundAssignmentsIncrementsAndTuplesAssignedToWrite() {
        checkHighlightRelated(#"
            //- /main.cj module=m package=m
            package m
            func f(): Int64 {
                var i = 0
            //      ^ write
                var j = 0
                i += 1
            //  ^ write
                i++
            //  ^ write
                (i, j) = (j, i)
            //   ^ write
            //               ^ read
                $0i
            //    ^ read
            }
            "#)
    }

    @TestCase
    func aLetIsNotWrittenAtItsDeclaration() {
        checkHighlightRelated(#"
            //- /main.cj module=m package=m
            package m
            func f(): Int64 {
                let k = 1
            //      ^ text
                $0k * k
            //    ^ read
            //        ^ read
            }
            "#)
    }

    @TestCase
    func ofOverloadsOnlyTheOneACallTakes() {
        // as definitionAt: the overload `calleeOf` chose, not every function of the name
        checkHighlightRelated(#"
            //- /main.cj module=m package=m
            package m
            func g(n: Int64): Int64 { n }
            //   ^ text
            func g(b: Bool): Int64 { 0 }
            func f(): Unit {
                $0g(1)
            //    ^ read
                g(true)
                g(2)
            //  ^ read
            }
            func h(): Int64 {
                g(3) + g(false)
            //  ^ read
            }
            "#)
    }

    @TestCase
    func aDeclarationHighlightsItsUses() {
        checkHighlightRelated(#"
            //- /main.cj module=m package=m
            package m
            func $0g(n: Int64): Int64 { n }
            //     ^ text
            func g(b: Bool): Int64 { 0 }
            func f(): Unit {
                g(1)
            //  ^ read
                g(true)
            }
            "#)
    }

    @TestCase
    func aTypeIsHighlightedInSignaturesAndBodies() {
        checkHighlightRelated(#"
            //- /main.cj module=m package=m
            package m
            class K {}
            //    ^ text
            func f(k: $0K): K {
            //          ^ text
            //              ^ text
                let other: K = k
            //             ^ text
                other
            }
            "#)
    }

    @TestCase
    func aParameterOfAPrimaryConstructorIsAMember() {
        checkHighlightRelated(#"
            //- /main.cj module=m package=m
            package m
            class P {
                P(var x: Int64) {}
            //        ^ write
                func reset(): Unit {
                    x = 0
            //      ^ write
                }
            }
            func f(p: P): Int64 {
                p.$0x
            //      ^ read
            }
            "#)
    }

    @TestCase
    func aNameMeaningNothingHighlightsNothing() {
        checkHighlightRelated(#"
            //- /main.cj module=m package=m
            package m
            func f(): Int64 {
                $0nothing + nothing
            }
            "#)
    }
}
