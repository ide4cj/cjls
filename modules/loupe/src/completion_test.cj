package loupe

import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.{TextRange, TokenAtOffset}
import loupe.fixture.*
import loupe.syntax.parse

/**
 * Checks the completions at the cursor of `fixture` are its annotations, under the name typed
 * before the cursor, or the token before it: `//^ label | kind | detail` per item, the most
 * relevant first; `//^ no completion` if there are none. With std's packages `std` read from the
 * SDK.
 */
func checkCompletion(fixture: String, std!: Array<String> = []): Unit {
    let parsed = Fixture.parse(fixture)
    let db =
        if (std.isEmpty()) {
            parsed.database()
        } else {
            parsed.database(binaries: std.map { name => stdCjoRead(name, stdCjo(name)) })
        }
    let cursor = parsed.cursor ?? throw FixtureException("no $0 in the fixture")
    let source = db.sourceFile(cursor.fileId).getOrThrow()
    let root = parse(db, source).syntaxNode()
    var left =
        match (root.tokenAtOffset(cursor.offset)) {
            case Single(token) => token
            case Between(token, _) => token
            case NoToken => throw FixtureException("no token at $0")
        }
    // the annotation goes under code: the token before the cursor, past the trivia
    while (left.kind.isTrivia()) {
        left = left.prevToken() ?? throw FixtureException("nothing before $0")
    }
    let annotations =
        match (completionsAt(db, cursor.fileId, cursor.offset)) {
            case Some(result) =>
                let range =
                    if (result.range.isEmpty()) {
                        left.textRange
                    } else {
                        result.range
                    }
                result
                    .items
                    .map {
                        item =>
                        let detail =
                            completionDetail(db, cursor.fileId, cursor.offset, item)
                                .map { one => " | ${one.code}" } ??
                                ""
                        let relevance = "${item.relevance}".padStart(3, padding: "0")
                        Annotation(
                            cursor.fileId,
                            range,
                            "${relevance} ${item.label} | ${item.kind}${detail}"
                        )
                    }
            case None => [Annotation(cursor.fileId, left.textRange, "no completion")]
        }
    expectAnnotations(fixture, annotations)
}

@Test
class CompletionTest {
    @TestCase
    func aDotOnALocalOfAGenericTypeListsItsMembersWithTheArgumentsSubstituted() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
            package m
            class Box<T> {
                let value: T
                init(value: T) { this.value = value }
                func get(): T { value }
                func put(value: T): Unit {}
                static func empty(): Box<T> { throw Exception() }
            }
            main() {
                let b = Box<Int64>(1)
                b.$0
            //   ^ 080 get | CompletionKind.FuncItem | func get(): Int64
            //   ^ 080 put | CompletionKind.FuncItem | func put(value: Int64): Unit
            //   ^ 080 value | CompletionKind.VarItem | let value: Int64
            }
            "#
        )
    }

    @TestCase
    func aDotOnATypeListsItsStaticMembersAndNotTheInstanceOnes() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
            package m
            class Box<T> {
                let value: T
                init(value: T) { this.value = value }
                func get(): T { value }
                static func empty(): Box<T> { throw Exception() }
            }
            enum Color {
                | Red | Rgb(Int64)
                func name(): String { "" }
            }
            main() {
                Box<Int64>.$0
            //            ^ 080 empty | CompletionKind.FuncItem | static func empty(): Box<Int64>
            }
            "#
        )
    }

    @TestCase
    func aDotOnThisListsTheInstanceMembersAndNotTheStaticOnes() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
            package m
            class Counter {
                var count = 0
                func bump(): Unit {
                    this.$0
            //          ^ 080 bump | CompletionKind.FuncItem | func bump(): Unit
            //          ^ 080 count | CompletionKind.VarItem | var count: Int64
                }
                static func zero(): Counter { Counter() }
            }
            "#
        )
    }

    @TestCase
    func anOperatorFunctionIsNotListedAfterADot() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
            package m
            struct Money {
                let cents = 0
                operator func +(other: Money): Money { this }
                operator func [](i: Int64): Int64 { i }
                func twice(): Money {
                    this.$0
            //          ^ 080 cents | CompletionKind.VarItem | let cents: Int64
            //          ^ 080 twice | CompletionKind.FuncItem | func twice(): Money
                }
            }
            "#
        )
    }

    @TestCase
    func aDotOnAnEnumListsItsConstructorsAndStaticMembers() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
            package m
            enum Color {
                | Red | Rgb(Int64)
                func name(): String { "" }
                static func all(): Array<Color> { [] }
            }
            main() {
                Color.$0
            //       ^ 080 Red | CompletionKind.CtorItem | Red
            //       ^ 080 Rgb | CompletionKind.CtorItem | Rgb(Int64)
            //       ^ 080 all | CompletionKind.FuncItem | static func all(): {unknown}
            }
            "#
        )
    }

    @TestCase
    func aDotOnAPackageListsWhatItExportsAndNotItsPrivateDeclarations() {
        checkCompletion(
            #"
            //- /lib.cj module=m package=m.lib
            package m.lib
            public func shown(): Int64 { 1 }
            private func hidden(): Int64 { 2 }
            public class Shape {}
            public let answer = 42
            //- /main.cj module=m package=m deps=m.lib
            package m
            import m.lib
            main() {
                lib.$0
            //     ^ 080 Shape | CompletionKind.ClassItem | public class Shape
            //     ^ 080 answer | CompletionKind.VarItem | public let answer: Int64
            //     ^ 080 shown | CompletionKind.FuncItem | public func shown(): Int64
            }
            "#
        )
    }

    @TestCase
    func aDotListsTheMembersOfAnExtendTheFileImportsTheInterfaceOfAndNotOfAnother() {
        checkCompletion(
            #"
            //- /shapes.cj module=m package=m.shapes
            package m.shapes
            public class Point {
                public func norm(): Int64 { 0 }
            }
            //- /named.cj module=m package=m.named
            package m.named
            import m.shapes.Point
            public interface Named {
                func name(): Int64
            }
            extend Point <: Named {
                public func name(): Int64 { 1 }
            }
            //- /loud.cj module=m package=m.loud
            package m.loud
            import m.shapes.Point
            public interface Loud {
                func shout(): Int64
            }
            extend Point <: Loud {
                public func shout(): Int64 { 2 }
            }
            //- /main.cj module=m package=m
            package m
            import m.shapes.Point
            import m.named.Named
            main() {
                let p = Point()
                p.$0
            //   ^ 080 name | CompletionKind.FuncItem | public func name(): Int64
            //   ^ 080 norm | CompletionKind.FuncItem | public func norm(): Int64
            }
            "#
        )
    }

    @TestCase
    func aPrivateMemberOfAnotherTypeIsNotListedAndOneOfTheTypeAroundIs() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
            package m
            class Other {
                private func hidden(): Unit {}
                public func shown(): Unit {}
            }
            class Own {
                private func mine(): Unit {}
                func use(other: Other) {
                    other.$0
            //           ^ 080 shown | CompletionKind.FuncItem | public func shown(): Unit
                }
            }
            "#
        )
    }

    @TestCase
    func aNameInABodyListsTheLocalsBeforeItAndNotThoseAfter() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
            package m
            func helper(): Unit {}
            main() {
                let before = 1
                let twice = before * 2
                be$0
            //  ^^ 010 break | CompletionKind.KeywordItem
            //  ^^ 010 continue | CompletionKind.KeywordItem
            //  ^^ 010 do | CompletionKind.KeywordItem
            //  ^^ 010 false | CompletionKind.KeywordItem
            //  ^^ 010 for | CompletionKind.KeywordItem
            //  ^^ 010 func | CompletionKind.KeywordItem
            //  ^^ 010 if | CompletionKind.KeywordItem
            //  ^^ 010 let | CompletionKind.KeywordItem
            //  ^^ 010 match | CompletionKind.KeywordItem
            //  ^^ 010 return | CompletionKind.KeywordItem
            //  ^^ 010 spawn | CompletionKind.KeywordItem
            //  ^^ 010 super | CompletionKind.KeywordItem
            //  ^^ 010 this | CompletionKind.KeywordItem
            //  ^^ 010 throw | CompletionKind.KeywordItem
            //  ^^ 010 true | CompletionKind.KeywordItem
            //  ^^ 010 try | CompletionKind.KeywordItem
            //  ^^ 010 unsafe | CompletionKind.KeywordItem
            //  ^^ 010 var | CompletionKind.KeywordItem
            //  ^^ 010 while | CompletionKind.KeywordItem
            //  ^^ 060 helper | CompletionKind.FuncItem | func helper(): Unit
            //  ^^ 060 main | CompletionKind.FuncItem | main(): Unit
            //  ^^ 099 before | CompletionKind.LocalItem | let before: Int64
            //  ^^ 100 twice | CompletionKind.LocalItem | let twice: Int64
                let after = 3
            }
            "#
        )
    }

    @TestCase
    func aNameInAMethodListsTheMembersOfTheTypeAroundAndItsTypeParameters() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
            package m
            class Counter<T> {
                var count = 0
                func bump(by: Int64): Unit {
                    c$0
            //      ^ 010 break | CompletionKind.KeywordItem
            //      ^ 010 continue | CompletionKind.KeywordItem
            //      ^ 010 do | CompletionKind.KeywordItem
            //      ^ 010 false | CompletionKind.KeywordItem
            //      ^ 010 for | CompletionKind.KeywordItem
            //      ^ 010 func | CompletionKind.KeywordItem
            //      ^ 010 if | CompletionKind.KeywordItem
            //      ^ 010 let | CompletionKind.KeywordItem
            //      ^ 010 match | CompletionKind.KeywordItem
            //      ^ 010 return | CompletionKind.KeywordItem
            //      ^ 010 spawn | CompletionKind.KeywordItem
            //      ^ 010 super | CompletionKind.KeywordItem
            //      ^ 010 this | CompletionKind.KeywordItem
            //      ^ 010 throw | CompletionKind.KeywordItem
            //      ^ 010 true | CompletionKind.KeywordItem
            //      ^ 010 try | CompletionKind.KeywordItem
            //      ^ 010 unsafe | CompletionKind.KeywordItem
            //      ^ 010 var | CompletionKind.KeywordItem
            //      ^ 010 while | CompletionKind.KeywordItem
            //      ^ 060 Counter | CompletionKind.ClassItem | class Counter<T>
            //      ^ 075 T | CompletionKind.TypeParamItem
            //      ^ 080 bump | CompletionKind.FuncItem | func bump(by: Int64): Unit
            //      ^ 080 count | CompletionKind.VarItem | var count: Int64
            //      ^ 080 zero | CompletionKind.FuncItem | static func zero(): Counter<T>
            //      ^ 099 by | CompletionKind.ParamItem | by: Int64
                }
                static func zero(): Counter<T> { Counter<T>() }
            }
            "#
        )
    }

    @TestCase
    func aNameOnALineOfItsOwnListsWhatIsInScopeThoughTheNextLineWouldBeItsMember() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
            package m
            class Point {
                let x = 1
                func norm(): Int64 { x }
            }
            main() {
                let p = Point()
                p.$0
            //   ^ 080 norm | CompletionKind.FuncItem | func norm(): Int64
            //   ^ 080 x | CompletionKind.VarItem | let x: Int64
                norm()
            }
            "#
        )
    }

    @TestCase
    func aNameListsNoConstructorOfAnEnumOnlyATestImports() {
        // N73 within what `cjpm build` compiles: it leaves the `*_test.cj` files out (N164, D129)
        checkCompletion(
            #"
            //- /lib.cj module=m package=m.lib
            package m.lib
            public enum Color { | Red | Green }
            //- /main_test.cj module=m package=m deps=m.lib
            package m
            import m.lib.Color
            //- /main.cj module=m package=m deps=m.lib
            package m
            main() {
                Re$0
            //  ^^ 010 break | CompletionKind.KeywordItem
            //  ^^ 010 continue | CompletionKind.KeywordItem
            //  ^^ 010 do | CompletionKind.KeywordItem
            //  ^^ 010 false | CompletionKind.KeywordItem
            //  ^^ 010 for | CompletionKind.KeywordItem
            //  ^^ 010 func | CompletionKind.KeywordItem
            //  ^^ 010 if | CompletionKind.KeywordItem
            //  ^^ 010 let | CompletionKind.KeywordItem
            //  ^^ 010 match | CompletionKind.KeywordItem
            //  ^^ 010 return | CompletionKind.KeywordItem
            //  ^^ 010 spawn | CompletionKind.KeywordItem
            //  ^^ 010 super | CompletionKind.KeywordItem
            //  ^^ 010 this | CompletionKind.KeywordItem
            //  ^^ 010 throw | CompletionKind.KeywordItem
            //  ^^ 010 true | CompletionKind.KeywordItem
            //  ^^ 010 try | CompletionKind.KeywordItem
            //  ^^ 010 unsafe | CompletionKind.KeywordItem
            //  ^^ 010 var | CompletionKind.KeywordItem
            //  ^^ 010 while | CompletionKind.KeywordItem
            //  ^^ 060 main | CompletionKind.FuncItem | main(): {unknown}
            }
            "#
        )
    }

    @TestCase
    func aNameAfterAnImportListsTheImportedAndTheGlob() {
        checkCompletion(
            #"
            //- /lib.cj module=m package=m.lib
            package m.lib
            public func shown(): Int64 { 1 }
            public func other(): Int64 { 2 }
            public enum Color { | Red | Green }
            //- /main.cj module=m package=m deps=m.lib
            package m
            import m.lib.shown
            import m.lib.Color
            main() {
                sh$0
            //  ^^ 010 break | CompletionKind.KeywordItem
            //  ^^ 010 continue | CompletionKind.KeywordItem
            //  ^^ 010 do | CompletionKind.KeywordItem
            //  ^^ 010 false | CompletionKind.KeywordItem
            //  ^^ 010 for | CompletionKind.KeywordItem
            //  ^^ 010 func | CompletionKind.KeywordItem
            //  ^^ 010 if | CompletionKind.KeywordItem
            //  ^^ 010 let | CompletionKind.KeywordItem
            //  ^^ 010 match | CompletionKind.KeywordItem
            //  ^^ 010 return | CompletionKind.KeywordItem
            //  ^^ 010 spawn | CompletionKind.KeywordItem
            //  ^^ 010 super | CompletionKind.KeywordItem
            //  ^^ 010 this | CompletionKind.KeywordItem
            //  ^^ 010 throw | CompletionKind.KeywordItem
            //  ^^ 010 true | CompletionKind.KeywordItem
            //  ^^ 010 try | CompletionKind.KeywordItem
            //  ^^ 010 unsafe | CompletionKind.KeywordItem
            //  ^^ 010 var | CompletionKind.KeywordItem
            //  ^^ 010 while | CompletionKind.KeywordItem
            //  ^^ 050 Color | CompletionKind.EnumItem | public enum Color
            //  ^^ 050 Green | CompletionKind.CtorItem | Green
            //  ^^ 050 Red | CompletionKind.CtorItem | Red
            //  ^^ 050 shown | CompletionKind.FuncItem | public func shown(): Int64
            //  ^^ 060 main | CompletionKind.FuncItem | main(): {unknown}
            }
            "#
        )
    }

    @TestCase
    func aBodyThatDoesNotParseStillCompletesTheLocalsBeforeTheCursor() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
            package m
            main() {
                let first = 1
                if (first > 0 {
                    let second = 2
                    fi$0
            //      ^^ 010 break | CompletionKind.KeywordItem
            //      ^^ 010 continue | CompletionKind.KeywordItem
            //      ^^ 010 do | CompletionKind.KeywordItem
            //      ^^ 010 false | CompletionKind.KeywordItem
            //      ^^ 010 for | CompletionKind.KeywordItem
            //      ^^ 010 func | CompletionKind.KeywordItem
            //      ^^ 010 if | CompletionKind.KeywordItem
            //      ^^ 010 let | CompletionKind.KeywordItem
            //      ^^ 010 match | CompletionKind.KeywordItem
            //      ^^ 010 return | CompletionKind.KeywordItem
            //      ^^ 010 spawn | CompletionKind.KeywordItem
            //      ^^ 010 super | CompletionKind.KeywordItem
            //      ^^ 010 this | CompletionKind.KeywordItem
            //      ^^ 010 throw | CompletionKind.KeywordItem
            //      ^^ 010 true | CompletionKind.KeywordItem
            //      ^^ 010 try | CompletionKind.KeywordItem
            //      ^^ 010 unsafe | CompletionKind.KeywordItem
            //      ^^ 010 var | CompletionKind.KeywordItem
            //      ^^ 010 while | CompletionKind.KeywordItem
            //      ^^ 060 main | CompletionKind.FuncItem | main(): Unit
            //      ^^ 097 first | CompletionKind.LocalItem | let first: Int64
            //      ^^ 100 second | CompletionKind.LocalItem | let second: Int64
                }
            }
            "#
        )
    }

    @TestCase
    func aCursorInATypeBodyOutsideAMemberListsTheKeywordsStartingAMember() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
            package m
            class Point {
                let x = 1
                pu$0
            //  ^^ 010 const | CompletionKind.KeywordItem
            //  ^^ 010 func | CompletionKind.KeywordItem
            //  ^^ 010 init | CompletionKind.KeywordItem
            //  ^^ 010 internal | CompletionKind.KeywordItem
            //  ^^ 010 let | CompletionKind.KeywordItem
            //  ^^ 010 mut | CompletionKind.KeywordItem
            //  ^^ 010 open | CompletionKind.KeywordItem
            //  ^^ 010 operator | CompletionKind.KeywordItem
            //  ^^ 010 override | CompletionKind.KeywordItem
            //  ^^ 010 private | CompletionKind.KeywordItem
            //  ^^ 010 prop | CompletionKind.KeywordItem
            //  ^^ 010 protected | CompletionKind.KeywordItem
            //  ^^ 010 public | CompletionKind.KeywordItem
            //  ^^ 010 redef | CompletionKind.KeywordItem
            //  ^^ 010 static | CompletionKind.KeywordItem
            //  ^^ 010 unsafe | CompletionKind.KeywordItem
            //  ^^ 010 var | CompletionKind.KeywordItem
            }
            "#
        )
    }

    @TestCase
    func aNameOnALineOfItsOwnAfterAnEnumsConstructorsListsTheKeywordsStartingAMember() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
            package m
            enum E {
                | A | B
                fu$0
            //  ^^ 010 const | CompletionKind.KeywordItem
            //  ^^ 010 func | CompletionKind.KeywordItem
            //  ^^ 010 init | CompletionKind.KeywordItem
            //  ^^ 010 internal | CompletionKind.KeywordItem
            //  ^^ 010 let | CompletionKind.KeywordItem
            //  ^^ 010 mut | CompletionKind.KeywordItem
            //  ^^ 010 open | CompletionKind.KeywordItem
            //  ^^ 010 operator | CompletionKind.KeywordItem
            //  ^^ 010 override | CompletionKind.KeywordItem
            //  ^^ 010 private | CompletionKind.KeywordItem
            //  ^^ 010 prop | CompletionKind.KeywordItem
            //  ^^ 010 protected | CompletionKind.KeywordItem
            //  ^^ 010 public | CompletionKind.KeywordItem
            //  ^^ 010 redef | CompletionKind.KeywordItem
            //  ^^ 010 static | CompletionKind.KeywordItem
            //  ^^ 010 unsafe | CompletionKind.KeywordItem
            //  ^^ 010 var | CompletionKind.KeywordItem
            }
            "#
        )
    }

    @TestCase
    func aNameAfterAPipeInAnEnumIsAConstructorAndCompletesNothing() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
            package m
            enum E {
                | A
                | fu$0
            //    ^^ no completion
            }
            "#
        )
    }

    @TestCase
    func theFirstNameOfAnEnumWithoutAPipeIsAConstructorAndCompletesNothing() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
            package m
            enum E {
                fu$0
            //  ^^ no completion
            }
            "#
        )
    }

    @TestCase
    func aCursorAtTheTopLevelListsTheKeywordsStartingADeclarationAndImportInThePreamble() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
              package m
              cl$0
            //^^ 010 abstract | CompletionKind.KeywordItem
            //^^ 010 class | CompletionKind.KeywordItem
            //^^ 010 const | CompletionKind.KeywordItem
            //^^ 010 enum | CompletionKind.KeywordItem
            //^^ 010 extend | CompletionKind.KeywordItem
            //^^ 010 foreign | CompletionKind.KeywordItem
            //^^ 010 func | CompletionKind.KeywordItem
            //^^ 010 import | CompletionKind.KeywordItem
            //^^ 010 interface | CompletionKind.KeywordItem
            //^^ 010 internal | CompletionKind.KeywordItem
            //^^ 010 let | CompletionKind.KeywordItem
            //^^ 010 macro | CompletionKind.KeywordItem
            //^^ 010 main | CompletionKind.KeywordItem
            //^^ 010 open | CompletionKind.KeywordItem
            //^^ 010 private | CompletionKind.KeywordItem
            //^^ 010 protected | CompletionKind.KeywordItem
            //^^ 010 public | CompletionKind.KeywordItem
            //^^ 010 sealed | CompletionKind.KeywordItem
            //^^ 010 struct | CompletionKind.KeywordItem
            //^^ 010 type | CompletionKind.KeywordItem
            //^^ 010 unsafe | CompletionKind.KeywordItem
            //^^ 010 var | CompletionKind.KeywordItem
            "#
        )
    }

    @TestCase
    func aCursorAtTheTopLevelAfterADeclarationListsNoImport() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
              package m
              func f(): Unit {}
              cl$0
            //^^ 010 abstract | CompletionKind.KeywordItem
            //^^ 010 class | CompletionKind.KeywordItem
            //^^ 010 const | CompletionKind.KeywordItem
            //^^ 010 enum | CompletionKind.KeywordItem
            //^^ 010 extend | CompletionKind.KeywordItem
            //^^ 010 foreign | CompletionKind.KeywordItem
            //^^ 010 func | CompletionKind.KeywordItem
            //^^ 010 interface | CompletionKind.KeywordItem
            //^^ 010 internal | CompletionKind.KeywordItem
            //^^ 010 let | CompletionKind.KeywordItem
            //^^ 010 macro | CompletionKind.KeywordItem
            //^^ 010 main | CompletionKind.KeywordItem
            //^^ 010 open | CompletionKind.KeywordItem
            //^^ 010 private | CompletionKind.KeywordItem
            //^^ 010 protected | CompletionKind.KeywordItem
            //^^ 010 public | CompletionKind.KeywordItem
            //^^ 010 sealed | CompletionKind.KeywordItem
            //^^ 010 struct | CompletionKind.KeywordItem
            //^^ 010 type | CompletionKind.KeywordItem
            //^^ 010 unsafe | CompletionKind.KeywordItem
            //^^ 010 var | CompletionKind.KeywordItem
            "#
        )
    }

    @TestCase
    func aCursorInsideAWordAtTheTopLevelCompletesNothing() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
              package m
              str$0uct Point {}
            //^^^^^^^^ no completion
            "#
        )
    }

    @TestCase
    func aParameterTypeListsTheTypesInScopeAndNotTheValues() {
        checkCompletion(
            #"
            //- /lib.cj module=m package=m.lib
            package m.lib
            public class Remote {}
            //- /main.cj module=m package=m
            package m
            import m.lib
            class Shape {}
            enum Color { | Red }
            func helper(): Unit {}
            let answer = 1
            func area<T>(s: S$0) {}
            //              ^ 020 Bool | CompletionKind.KeywordItem
            //              ^ 020 Float16 | CompletionKind.KeywordItem
            //              ^ 020 Float32 | CompletionKind.KeywordItem
            //              ^ 020 Float64 | CompletionKind.KeywordItem
            //              ^ 020 Int16 | CompletionKind.KeywordItem
            //              ^ 020 Int32 | CompletionKind.KeywordItem
            //              ^ 020 Int64 | CompletionKind.KeywordItem
            //              ^ 020 Int8 | CompletionKind.KeywordItem
            //              ^ 020 IntNative | CompletionKind.KeywordItem
            //              ^ 020 Nothing | CompletionKind.KeywordItem
            //              ^ 020 Rune | CompletionKind.KeywordItem
            //              ^ 020 UInt16 | CompletionKind.KeywordItem
            //              ^ 020 UInt32 | CompletionKind.KeywordItem
            //              ^ 020 UInt64 | CompletionKind.KeywordItem
            //              ^ 020 UInt8 | CompletionKind.KeywordItem
            //              ^ 020 UIntNative | CompletionKind.KeywordItem
            //              ^ 020 Unit | CompletionKind.KeywordItem
            //              ^ 050 lib | CompletionKind.PkgItem
            //              ^ 060 Color | CompletionKind.EnumItem | enum Color
            //              ^ 060 Shape | CompletionKind.ClassItem | class Shape
            //              ^ 085 T | CompletionKind.TypeParamItem
            "#
        )
    }

    @TestCase
    func aTypeAnnotationInABodyListsTheTypeParametersOfTheTypeAround() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
            package m
            class Box<T> {
                func put<U>(value: U): Unit {
                    let x: B$0
            //             ^ 020 Bool | CompletionKind.KeywordItem
            //             ^ 020 Float16 | CompletionKind.KeywordItem
            //             ^ 020 Float32 | CompletionKind.KeywordItem
            //             ^ 020 Float64 | CompletionKind.KeywordItem
            //             ^ 020 Int16 | CompletionKind.KeywordItem
            //             ^ 020 Int32 | CompletionKind.KeywordItem
            //             ^ 020 Int64 | CompletionKind.KeywordItem
            //             ^ 020 Int8 | CompletionKind.KeywordItem
            //             ^ 020 IntNative | CompletionKind.KeywordItem
            //             ^ 020 Nothing | CompletionKind.KeywordItem
            //             ^ 020 Rune | CompletionKind.KeywordItem
            //             ^ 020 UInt16 | CompletionKind.KeywordItem
            //             ^ 020 UInt32 | CompletionKind.KeywordItem
            //             ^ 020 UInt64 | CompletionKind.KeywordItem
            //             ^ 020 UInt8 | CompletionKind.KeywordItem
            //             ^ 020 UIntNative | CompletionKind.KeywordItem
            //             ^ 020 Unit | CompletionKind.KeywordItem
            //             ^ 060 Box | CompletionKind.ClassItem | class Box<T>
            //             ^ 075 T | CompletionKind.TypeParamItem
            //             ^ 085 U | CompletionKind.TypeParamItem
                }
            }
            "#
        )
    }

    @TestCase
    func aTypeAfterAnImportedPackageListsTheTypesItExports() {
        checkCompletion(
            #"
            //- /lib.cj module=m package=m.lib
            package m.lib
            public class Remote {}
            public interface Shown {}
            public func notAType(): Unit {}
            class Hidden {}
            //- /main.cj module=m package=m
            package m
            import m.lib
            main() {
                let x: lib.$0
            //            ^ 080 Remote | CompletionKind.ClassItem | public class Remote
            //            ^ 080 Shown | CompletionKind.InterfaceItem | public interface Shown
            }
            "#
        )
    }

    @TestCase
    func anImportListsTheNextSegmentOfThePackagesTheModuleSees() {
        checkCompletion(
            #"
            //- /lib.cj module=m package=m.lib
            package m.lib
            public func shown(): Unit {}
            //- /deep.cj module=m package=m.lib.deep
            package m.lib.deep
            //- /util.cj module=m package=m.util
            package m.util
            //- /other.cj module=other package=other
            package other
            //- /main.cj module=m package=m
            package m
            import m.$0
            //      ^ 070 lib | CompletionKind.PkgItem
            //      ^ 070 util | CompletionKind.PkgItem
            "#
        )
    }

    @TestCase
    func anImportAfterAPackageListsItsSubpackagesAndWhatItExports() {
        checkCompletion(
            #"
            //- /lib.cj module=m package=m.lib
            package m.lib
            public func shown(): Unit {}
            public class Shape {}
            func hidden(): Unit {}
            //- /deep.cj module=m package=m.lib.deep
            package m.lib.deep
            //- /main.cj module=m package=m
            package m
            import m.{lib.$0}
            //           ^ 070 deep | CompletionKind.PkgItem
            //           ^ 080 Shape | CompletionKind.ClassItem | public class Shape
            //           ^ 080 shown | CompletionKind.FuncItem | public func shown(): Unit
            "#
        )
    }

    @TestCase
    func aFunctionNamedInATypeBodyListsTheMembersOfItsSupertypesItMayOverride() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
            package m
            interface Shape {
                func area(): Int64
                func name(): Int64
                prop sides: Int64
            }
            open class Base {
                public open func draw(): Unit {}
                public func fixed(): Unit {}
                private open func secret(): Unit {}
                public static func make(): Unit {}
            }
            class Square <: Base & Shape {
                public func name(): Int64 { 0 }
                public prop sides: Int64 { get() { 4 } }
                public override func $0
            //                  ^^^^ 080 area | CompletionKind.FuncItem | func area(): Int64
            //                  ^^^^ 080 draw | CompletionKind.FuncItem | public open func draw(): Unit
            }
            "#
        )
    }

    @TestCase
    func aCursorInACommentCompletesNothing() {
        checkCompletion(
            #"
            //- /main.cj module=m package=m
            package m
            main() {
                let x = 1
            //          ^ no completion
                // x.$0
            }
            "#
        )
    }
}
