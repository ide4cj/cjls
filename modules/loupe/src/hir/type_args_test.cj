package loupe.hir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*
import loupe.syntax.parse

/**
 * Checks the types of calls to `pick` in `f`, rather than the annotated locals receiving them.
 */
private func checkPickCalls(fixture: String): Unit {
    let (db, source, f) =
        declOf(fixture, "f", binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
    let lowered = bodyWithSourceMap(db, f)
    let root = parse(db, source).syntaxNode()
    let result = inferBody(db, f)
    let actual = ArrayList<Annotation>()
    for (i in 0..lowered.body.exprs.size) {
        if (
            let CallExpr(callee, _) <- lowered.body.exprs[i] &&
                let PathExpr("pick", _) <- lowered.body[callee]
        ) {
            let origin = lowered.sourceMap.exprs[i].written.getOrThrow()
            let node = origin.ptr.tryToNode(root).getOrThrow()
            let ty = result[ExprId(i)].getOrThrow()
            @Expect(!hasInferVars(db, ty))
            actual.add(Annotation(source.fileId(db), node.textRange, ty.text(db)))
        }
    }
    expectAnnotations(fixture, actual.toArray())
}

@Test
class TypeArgTest {
    @TestCase
    func anExpectedTypeResolvesAnAmbiguousJoin() {
        checkPickCalls(
            #"
            package m
            interface I {}
            interface J {}
            class A <: I & J {}
            class B <: I & J {}
            func pick<T>(a: T, b: T): T { a }
            func f(): Unit {
                let x: I = pick(A(), B())
            //             ^^^^^^^^^^^^^^ I
                let z: ?I = pick(A(), B())
            //              ^^^^^^^^^^^^^^ Option<I>
                // cjc: unable to infer generic argument of this function
                let y = pick(A(), B())
            //          ^^^^^^^^^^^^^^ {unknown}
            }
            "#
        )
    }

    @TestCase
    func aDeclaredBoundResolvesAnAmbiguousJoin() {
        checkPickCalls(
            #"
            package m
            interface I {}
            interface J {}
            class A <: I & J {}
            class B <: I & J {}
            func pick<T>(a: T, b: T): T where T <: I { a }
            func f(): Unit {
                let x = pick(A(), B())
            //          ^^^^^^^^^^^^^^ I
                let y: ?I = pick(A(), B())
            //              ^^^^^^^^^^^^^^ I
            }
            "#
        )
    }

    @TestCase
    func everyLowerBoundMustFitTheUpperBound() {
        checkPickCalls(
            #"
            package m
            interface I {}
            class A <: I {}
            class B {}
            func pick<T>(a: T, b: T): T { a }
            func f(): Unit {
                // cjc: unable to infer generic argument of this function
                let x: I = pick(A(), B())
            //             ^^^^^^^^^^^^^^ {unknown}
            }
            "#
        )
    }

    @TestCase
    func incomparableUpperBoundsDoNotResolveAnAmbiguousJoin() {
        checkPickCalls(
            #"
            package m
            interface I {}
            interface J {}
            class A <: I & J {}
            class B <: I & J {}
            func pick<T>(a: T, b: T): T where T <: I & J { a }
            func f(): Unit {
                // cjc: unable to infer generic argument of this function
                let x = pick(A(), B())
            //          ^^^^^^^^^^^^^^ {unknown}
            }
            "#
        )
    }

    @TestCase
    func numericLiteralsKeepTheirKindAndConcreteArgumentType() {
        checkPickCalls(
            #"
            package m
            func pick<T>(a: T, b: T): T { a }
            func f(): Unit {
                let x: ToString = pick(1, 2u8)
            //                    ^^^^^^^^^^^^ UInt8
                // cjc: unable to infer generic argument of this function
                let y: UInt8 = pick(1, 2.0)
            //                 ^^^^^^^^^^^^ {unknown}
            }
            "#
        )
    }

    @TestCase
    func anUpperBoundCanAcceptDefaultedNumericLiterals() {
        checkPickCalls(
            #"
            package m
            func pick<T>(a: T, b: T): T { a }
            func f(): Unit {
                let x: ToString = pick(1, true)
            //                    ^^^^^^^^^^^^^ ToString
                let y: ToString = pick(1.0, 2u8)
            //                    ^^^^^^^^^^^^^^ ToString
                let z: ToString = pick(1, 2.0)
            //                    ^^^^^^^^^^^^ ToString
                // cjc: unable to infer generic argument of this function
                let bad = pick(1, 2.0)
            //            ^^^^^^^^^^^^ {unknown}
            }
            "#
        )
    }

    @TestCase
    func aValidJoinIsPreferredToAWiderUpperBound() {
        checkPickCalls(
            #"
            package m
            interface I {}
            open class Base <: I {}
            class A <: Base {}
            class B <: Base {}
            func pick<T>(a: T, b: T): T { a }
            func f(): Unit {
                let x: I = pick(A(), B())
            //             ^^^^^^^^^^^^^^ Base
            }
            "#
        )
    }
}
