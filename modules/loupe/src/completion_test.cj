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
    let db = if (std.isEmpty()) {
        parsed.database()
    } else {
        parsed.database(binaries: std.map {name => stdCjoRead(name, stdCjo(name))})
    }
    let cursor = parsed.cursor ?? throw FixtureException("no $0 in the fixture")
    let source = db.sourceFile(cursor.fileId).getOrThrow()
    let root = parse(db, source).syntaxNode()
    var left = match (root.tokenAtOffset(cursor.offset)) {
        case Single(token) => token
        case Between(token, _) => token
        case NoToken => throw FixtureException("no token at $0")
    }
    // the annotation goes under code: the token before the cursor, past the trivia
    while (left.kind.isTrivia()) {
        left = left.prevToken() ?? throw FixtureException("nothing before $0")
    }
    let annotations = match (completionsAt(db, cursor.fileId, cursor.offset)) {
        case Some(result) =>
            let range = if (result.range.isEmpty()) {
                left.textRange
            } else {
                result.range
            }
            result.items.map {
                item =>
                let detail = completionDetail(db, cursor.fileId, cursor.offset, item).map {one => " | ${one.code}"} ?? ""
                let relevance = "${item.relevance}".padStart(3, padding: "0")
                Annotation(cursor.fileId, range, "${relevance} ${item.label} | ${item.kind}${detail}")
            }
        case None => [Annotation(cursor.fileId, left.textRange, "no completion")]
    }
    expectAnnotations(fixture, annotations)
}

@Test
class CompletionTest {
    @TestCase
    func aDotOnALocalOfAGenericTypeListsItsMembersWithTheArgumentsSubstituted() {
        checkCompletion(#"
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
            "#)
    }

    @TestCase
    func aDotOnATypeListsItsStaticMembersAndNotTheInstanceOnes() {
        checkCompletion(#"
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
            "#)
    }

    @TestCase
    func aDotOnThisListsTheInstanceMembersAndNotTheStaticOnes() {
        checkCompletion(#"
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
            "#)
    }

    @TestCase
    func aDotOnAnEnumListsItsConstructorsAndStaticMembers() {
        checkCompletion(#"
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
            "#)
    }

    @TestCase
    func aDotOnAPackageListsWhatItExportsAndNotItsPrivateDeclarations() {
        checkCompletion(#"
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
            "#)
    }

    @TestCase
    func aPrivateMemberOfAnotherTypeIsNotListedAndOneOfTheTypeAroundIs() {
        checkCompletion(#"
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
            "#)
    }

    @TestCase
    func aNameInABodyListsTheLocalsBeforeItAndNotThoseAfter() {
        checkCompletion(#"
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
            "#)
    }

    @TestCase
    func aNameInAMethodListsTheMembersOfTheTypeAroundAndItsTypeParameters() {
        checkCompletion(#"
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
            "#)
    }

    @TestCase
    func aNameOnALineOfItsOwnListsWhatIsInScopeThoughTheNextLineWouldBeItsMember() {
        checkCompletion(#"
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
            "#)
    }

    @TestCase
    func aNameAfterAnImportListsTheImportedAndTheGlob() {
        checkCompletion(#"
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
            "#)
    }

    @TestCase
    func aBodyThatDoesNotParseStillCompletesTheLocalsBeforeTheCursor() {
        checkCompletion(#"
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
            "#)
    }

    @TestCase
    func aCursorInATypeBodyOutsideAMemberCompletesNothing() {
        checkCompletion(#"
            //- /main.cj module=m package=m
            package m
            class Point {
                let x = 1
            //          ^ no completion
                $0
            }
            "#)
    }

    @TestCase
    func aCursorInACommentCompletesNothing() {
        checkCompletion(#"
            //- /main.cj module=m package=m
            package m
            main() {
                let x = 1
            //          ^ no completion
                // x.$0
            }
            "#)
    }
}
