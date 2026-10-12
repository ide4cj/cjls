package loupe

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.SyntaxElement
import cjsyntax.{CjSyntaxToken, SyntaxKind}
import loupe.db.BinaryModel
import loupe.vfs.CjoFileRead
import loupe.fixture.*
import loupe.syntax.parse

/**
 * Checks what each name of `fixture` at its use, and each lone name a pattern binds, is highlighted
 * as is its annotation: `//^ Tag[modifiers]`, `//^ none` for a name given no token.
 */
func checkHighlight(fixture: String, binaries!: Array<CjoFileRead> = [], models!: Array<BinaryModel> = []): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database(binaries: binaries, models: models)
    let actual = ArrayList<Annotation>()
    for (file in parsed.files) {
        let found = HashMap<Int64, HighlightedRange>()
        for (one in highlight(db, file.fileId)) {
            found.add(one.range.start, one)
        }
        let root = parse(db, db.sourceFile(file.fileId).getOrThrow()).syntaxNode()
        let tokens = root.descendantsWithTokens() |> filterMap {
            element: SyntaxElement<SyntaxKind> => match (element) {
                case SyntaxElement.Token(token) where isUse(token) => Some(token)
                case _ => Option<CjSyntaxToken>.None
            }
        }
        for (token in tokens) {
            let text = match (found.get(token.textRange.start)) {
                case Some(one) where one.modifiers.isEmpty() => one.tag.toString()
                case Some(one) => "${one.tag}[${one.modifiers}]"
                case None => "none"
            }
            actual.add(Annotation(file.fileId, token.textRange, text))
        }
    }
    expectAnnotations(fixture, actual.toArray())
}

/**
 * A name at its use but an annotation's, or a lone name a pattern binds: what resolution tells.
 */
func isUse(token: CjSyntaxToken): Bool {
    let name = token.parent
    let owner = name.parent?.kind
    token.kind == SyntaxKind.Ident && (name.kind == SyntaxKind.NameRef && owner != Some(SyntaxKind.Annotation) ||
        name.kind == SyntaxKind.Name && owner == Some(SyntaxKind.BindPat))
}

/**
 * A name at its use highlighted by what it means (#201, D72).
 */
@Test
class HighlightResolvedTest {
    @TestCase
    func localsAndParametersByWhatDeclaresThem() {
        checkHighlight(#"
            //- /main.cj module=m package=m
            package m
            //      ^ Namespace
            func f(p: Int64): Int64 {
                let a = p
            //          ^ Parameter
                var b = a
            //          ^ Variable[Readonly]
                b = b + 1
            //  ^ Variable[Mutable]
            //      ^ Variable[Mutable]
                let g = {q: Int64 => q + b}
            //                       ^ Parameter
            //                           ^ Variable[Mutable]
                func h(): Int64 { a }
            //                    ^ Variable[Readonly]
                g(h())
            //  ^ Variable[Readonly]
            //    ^ Function
            }
            "#)
    }

    @TestCase
    func membersOfTheTypeAroundAndAfterADot() {
        checkHighlight(#"
            //- /main.cj module=m package=m
            package m
            //      ^ Namespace
            class C {
                let x: Int64 = 1
                var y: Int64 = 2
                C(let z: Int64, var w: Int64) {}
                static func make(): C { C(0, 0) }
            //                      ^ Class
            //                          ^ Class
                prop p: Int64 { get() { x + y + z + w } }
            //                          ^ Field[Readonly]
            //                              ^ Field[Mutable]
            //                                  ^ Field[Readonly]
            //                                      ^ Field[Mutable]
                func m(): Int64 { p }
            //                    ^ Property
            }
            func f(c: C): Int64 {
            //        ^ Class
                let d = C.make()
            //          ^ Class
            //            ^^^^ Method[Static]
                c.x + d.y + c.z + c.w + c.p + c.m()
            //  ^ Parameter
            //    ^ Field[Readonly]
            //        ^ Variable[Readonly]
            //          ^ Field[Mutable]
            //              ^ Parameter
            //                ^ Field[Readonly]
            //                    ^ Parameter
            //                      ^ Field[Mutable]
            //                          ^ Parameter
            //                            ^ Property
            //                                ^ Parameter
            //                                  ^ Method
            }
            "#)
    }

    @TestCase
    func typesByTheirKindAndTypeParameters() {
        checkHighlight(#"
            //- /main.cj module=m package=m
            package m
            //      ^ Namespace
            class C {}
            struct S {}
            interface I {}
            enum E { | A | B(Int64) }
            type T = C
            //       ^ Class
            func f<X>(c: C, s: S, i: I, e: E, t: T, x: X): Unit where X <: I {}
            //           ^ Class
            //                 ^ Struct
            //                       ^ Interface
            //                             ^ Enum
            //                                   ^ TypeAlias
            //                                         ^ TypeParameter
            //                                                        ^ TypeParameter
            //                                                             ^ Interface
            "#)
    }

    @TestCase
    func enumConstructorsInExpressionsAndPatterns() {
        checkHighlight(#"
            //- /main.cj module=m package=m
            package m
            //      ^ Namespace
            enum E { | A | B(Int64) }
            func f(e: E): Int64 {
            //        ^ Enum
                match (e) {
            //         ^ Parameter
                    case A => 0
            //           ^ EnumConstructor
                    case B(n) => n
            //           ^ EnumConstructor
            //             ^ Variable[Declaration]
            //                   ^ Variable
                }
            }
            func g(): E { if (true) { A } else { E.B(1) } }
            //        ^ Enum
            //                        ^ EnumConstructor
            //                                   ^ Enum
            //                                     ^ EnumConstructor
            "#)
    }

    @TestCase
    func globalsFunctionsAndConstants() {
        checkHighlight(#"
            //- /main.cj module=m package=m
            package m
            //      ^ Namespace
            let r = 1
            var w = 2
            const K = 3
            @Deprecated
            func old(): Int64 { 0 }
            func f(): Int64 { r + w + K + old() }
            //                ^ Variable[Readonly]
            //                    ^ Variable[Mutable]
            //                        ^ Constant[Readonly]
            //                            ^^^ Function[Deprecated]
            "#)
    }

    @TestCase
    func aNameThatMeansNothingIsAnUnresolvedReference() {
        checkHighlight(#"
            //- /main.cj module=m package=m
            package m
            //      ^ Namespace
            func f(): Unit {
                let x = missing
            //          ^^^^^^^ UnresolvedReference
                let y: Missing = x
            //         ^^^^^^^ UnresolvedReference
            //                   ^ Variable[Readonly]
                nope()
            //  ^^^^ UnresolvedReference
            }
            "#)
    }

    @TestCase
    func aMemberNothingHasAfterADotIsNoUnresolvedReference() {
        // a macro called on the type may add it, as `@Derive` does
        checkHighlight(#"
            //- /main.cj module=m package=m
            package m
            //      ^ Namespace
            class C {}
            func f(c: C): Unit { c.missing }
            //        ^ Class
            //                   ^ Parameter
            //                     ^^^^^^^ none
            "#)
    }

    @TestCase
    func aNameInAPackageCallingAMacroOfItsOwnIsNoUnresolvedReference() {
        // the macro may declare it, and the workspace's are not run yet (#176)
        checkHighlight(#"
            //- /main.cj module=m package=m
              package m
            //        ^ Namespace
              @Generate
            // ^^^^^^^^ MacroCall
              class A {}
              func f(): Unit { generated() }
            //                 ^^^^^^^^^ none
            "#)
    }

    @TestCase
    func packagesInTheHeaderImportsAndPaths() {
        checkHighlight(#"
            //- /a.cj module=m package=m.a
            package m.a
            //      ^ Namespace
            //        ^ Namespace
            public class A {}
            public func make(): A { A() }
            //                  ^ Class
            //                      ^ Class
            //- /b.cj module=m package=m.b
            package m.b
            //      ^ Namespace
            //        ^ Namespace
            import m.a
            //     ^ Namespace
            //       ^ none
            import m.a.A
            //     ^ Namespace
            //       ^ Namespace
            //         ^ none
            func f(x: a.A, y: A): Unit {}
            //        ^ Namespace
            //          ^ Class
            //                ^ Class
            func g(): A { a.make() }
            //        ^ Class
            //            ^ Namespace
            //              ^^^^ Function
            "#)
    }

    @TestCase
    func aMutablePropertyAndACaughtException() {
        checkHighlight(#"
            //- /main.cj module=m package=m
            package m
            //      ^ Namespace
            class C {
                mut prop q: Int64 { get() { 0 } set(v) {} }
            }
            func f(c: C): Int64 {
            //        ^ Class
                try { c.q } catch (e: Exception) { 0 }
            //        ^ Parameter
            //          ^ Property[Mutable]
            //                        ^^^^^^^^^ Class[DefaultLibrary]
            }
            "#, binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
    }
}

@Test
class HighlightStdTest {
    @TestCase
    func aDeclarationOfStdIsOfTheDefaultLibrary() {
        checkHighlight(#"
            //- /main.cj module=m package=m
            package m
            //      ^ Namespace
            main() {
                let s: String = "x"
            //         ^^^^^^ Struct[DefaultLibrary]
                let o: Option<Int64> = Some(s.size)
            //         ^^^^^^ Enum[DefaultLibrary]
            //                         ^^^^ EnumConstructor[DefaultLibrary]
            //                              ^ Variable[Readonly]
            //                                ^^^^ Property[DefaultLibrary]
                println(s)
            //  ^^^^^^^ Function[DefaultLibrary]
            //          ^ Variable[Readonly]
            }
            "#, binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
    }

    @TestCase
    func aNameThatMeansNothingWhereOnlyStdsMacrosAreCalledIsUnresolved() {
        // std's macros declare no name a body uses; a type of the compiler's own is of the default library
        checkHighlight(#"
            //- /main.cj module=m package=m
              package m
            //        ^ Namespace
              import std.deriving.*
            //       ^^^ Namespace
            //           ^^^^^^^^ Namespace
              @Derive[Equatable]
            // ^^^^^^ Macro[DefaultLibrary]
              class P {}
              func f(xs: Array<Int64>): Unit { missing }
            //           ^^^^^ Struct[DefaultLibrary]
            //                                 ^^^^^^^ UnresolvedReference
            "#, binaries: ["std.core", "std.deriving"].map {name => stdCjoRead(name, stdCjo(name))})
    }
}
