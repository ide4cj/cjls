package loupe

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange
import loupe.db.{MappedSpan, SpanOrigin}
import loupe.fixture.*
import loupe.syntax.parse

/**
 * Checks what hovering the name at the cursor of `fixture` shows is its annotations: `//^ code in
 * path — doc` under the name for each thing it stands for, the lines of its doc joined by ` / `;
 * `//^ no hover` if it shows nothing. With std's packages `std` read from the SDK, and their sources
 * from `.corpora/` if `sources`.
 */
func checkHover(fixture: String, std!: Array<String> = [], sources!: Bool = false): Unit {
    let parsed = Fixture.parse(fixture)
    let db = if (std.isEmpty()) {
        parsed.database()
    } else if (sources) {
        parsed.database(binaries: std.map {name => stdCjoRead(name, stdCjo(name))}, models: [stdWithSources(std)])
    } else {
        parsed.database(binaries: std.map {name => stdCjoRead(name, stdCjo(name))})
    }
    let cursor = parsed.cursor ?? throw FixtureException("no $0 in the fixture")
    let annotations = match (hoverAt(db, cursor.fileId, cursor.offset)) {
        case Some(hover) => hover.items.map {item => Annotation(cursor.fileId, hover.range, hoverText(item))}
        case None =>
            let source = db.sourceFile(cursor.fileId).getOrThrow()
            let token = tokenAt(parse(db, source).syntaxNode(), cursor.offset) ?? throw FixtureException("no name at $0")
            [Annotation(cursor.fileId, token.textRange, "no hover")]
    }
    expectAnnotations(fixture, annotations)
}

func hoverText(item: HoverItem): String {
    let path = item.path.map {one => " in ${one}"} ?? ""
    let doc = item.doc.map {one => " — ${one.replace("\n", " / ")}"} ?? ""
    "${item.code}${path}${doc}"
}

@Test
class HoverTest {
    @TestCase
    func aFunctionCalledShowsItsSignatureItsPackageAndItsDoc() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            /**
             * Adds `y` to `x`.
             *
             * @param x the first
             */
            public func add(x: Int64, y!: Int64): Int64 { x + y }
            main() {
                $0add(1, y: 2)
            //    ^^^ public func add(x: Int64, y!: Int64): Int64 in m — Adds `y` to `x`. /  / @param x the first
            }
            "#)
    }

    @TestCase
    func aDeclarationAtItsNameShowsItself() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            // a line comment documents too
            func $0twice<T>(x: T): Array<T> where T <: ToString { [x, x] }
            //     ^^^^^ func twice<T>(x: T): Array<T> where T <: ToString in m — a line comment documents too
            "#, std: ["std.core"])
    }

    @TestCase
    func aLocalShowsTheTypeInferredForIt() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            main() {
                var x = 1.5
                $0x
            //    ^ var x: Float64
            }
            "#)
    }

    @TestCase
    func aLocalAtItsDeclaration() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            main() {
                let $0s = "a"
            //        ^ let s: String
            }
            "#, std: ["std.core"])
    }

    @TestCase
    func aParameterShowsItsType() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            func f(n: Int64): Int64 {
                $0n + 1
            //    ^ n: Int64
            }
            "#)
    }

    @TestCase
    func aLambdasParameterShowsTheTypeExpectedOfIt() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            func apply(f: (Int64) -> Bool): Bool { f(1) }
            main() {
                apply {n => $0n > 0}
            //                ^ n: Int64
            }
            "#)
    }

    @TestCase
    func aCallOfOverloadsShowsTheOneItTakes() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            /** of a number */
            func show(n: Int64): String { "" }
            /** of a string */
            func show(s: String): String { s }
            main() {
                $0show("a")
            //    ^^^^ func show(s: String): String in m — of a string
            }
            "#, std: ["std.core"])
    }

    @TestCase
    func aMemberOfAGenericTypeShowsItsTypesAsAMemberOfTheValue() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            class Box<T> {
                Box(var value: T) {}
                public func get(): T { value }
                public func put(other: T): Unit { value = other }
            }
            main() {
                let box = Box<String>("a")
                box.$0put("b")
            //        ^^^ public func put(other: String): Unit in m.Box
            }
            "#, std: ["std.core"])
    }

    @TestCase
    func aMemberParameterOfAGenericTypeAsAMemberOfTheValue() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            class Box<T> {
                Box(var value: T) {}
            }
            main() {
                let box = Box<String>("a")
                box.$0value
            //        ^^^^^ var value: String in m.Box
            }
            "#, std: ["std.core"])
    }

    @TestCase
    func aTypeShowsItsDeclaration() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            interface I {}
            open class Base {}
            /** a class */
            public class C <: Base & I {}
            func f(c: $0C): Unit {}
            //          ^ public class C <: Base & I in m — a class
            "#)
    }

    @TestCase
    func aClassOfNoSuperclassShowsNoObject() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            class C<T> {}
            func f(c: $0C<Int64>): Unit {}
            //          ^ class C<T> in m
            "#)
    }

    @TestCase
    func anAliasShowsWhatItNames() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            type Pair = (Int64, String)
            func f(p: $0Pair): Unit {}
            //          ^^^^ type Pair = (Int64, String) in m
            "#, std: ["std.core"])
    }

    @TestCase
    func aTypeParameterNothingBoundsHasNoHover() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            func f<T>(x: $0T): T { x }
            //             ^ no hover
            "#)
    }

    @TestCase
    func aTypeParameterShowsWhatItsWhereBoundsItBy() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            interface I {}
            interface J {}
            func f<T, U>(x: $0T, y: U): T where T <: I, U <: J, T <: J { x }
            //                ^ T <: I & J
            "#)
    }

    @TestCase
    func aTypeParameterOfAnExtendShowsTheExtendsBounds() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            interface I {}
            class Box<T> {}
            extend<T> Box<T> where T <: I {
                func get(x: $0T): T { x }
            //              ^ T <: I
            }
            "#)
    }

    @TestCase
    func aTypeParameterOfALocalFunctionShowsItsBounds() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            interface I {}
            main() {
                func g<T>(x: $0T): T where T <: I { x }
            //                 ^ T <: I
            }
            "#)
    }

    @TestCase
    func anEnumConstructorShowsItsParametersAndItsEnum() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            enum Shape {
                | Circle(Float64)
                | Square
            }
            main() {
                let s = $0Circle(1.0)
            //            ^^^^^^ Circle(Float64) in m.Shape
            }
            "#)
    }

    @TestCase
    func aVariableOfThePackageShowsTheTypeInferredForIt() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            public let limit = 10
            main() {
                $0limit
            //    ^^^^^ public let limit: Int64 in m
            }
            "#)
    }

    @TestCase
    func aPropertyOfAStruct() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            struct P {
                public mut prop size: Int64 {
                    get() { 0 }
                    set(v) {}
                }
            }
            func f(p: P): Int64 {
                p.$0size
            //      ^^^^ public mut prop size: Int64 in m.P
            }
            "#)
    }

    @TestCase
    func aLocalFunctionShowsItsSignature() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            main() {
                func twice(n: Int64) { n * 2 }
                $0twice(1)
            //    ^^^^^ func twice(n: Int64): Int64
            }
            "#)
    }

    @TestCase
    func aNameNothingResolvesShowsNothing() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            main() {
                $0nowhere
            //    ^^^^^^^ no hover
            }
            "#)
    }

    @TestCase
    func aDeclarationInAMacroCallShowsTheDocBeforeTheCall() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            /** a struct */
            @Derive[Equatable]
            struct S {}
            func g(s: $0S): Unit {}
            //          ^ struct S in m — a struct
            "#)
    }

    @TestCase
    func aTypeShowsTheInterfacesItsDeriveAdds() {
        // arrange
        let parsed = Fixture.parse(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            /** a struct */
            @Derive[Equatable, Hashable]
            struct S <: ToString {
                public func toString(): String { "" }
            }
            func g(s: $0S): Unit {}
            "#)
        let db = deriveDatabase(parsed)
        let cursor = parsed.cursor.getOrThrow()

        // act
        let sut = hoverAt(db, cursor.fileId, cursor.offset)

        // assert
        @Expect(sut?.items.map {item => hoverText(item)}, Some(["struct S <: ToString & Equatable<S> & Hashable in m — a struct"]))
    }

    @TestCase
    func aDeclarationAWorkspaceMacroCopiedShowsWhatItAddedAndTheDocBeforeTheCallAtItsUsesAndAtItself() {
        // arrange
        let (db, file) = expansionDatabase(#"
            package m
            import m.ms.*
            /** a class */
            @M[x]
            class C {}
            func f(c: C): Unit {}
            "#)
        let copied = match (requestFor(db, file, "M").input.spans[0].origin) {
            case FromSource(range) => range
            case _ => throw FixtureException("the input of @M is not its class")
        }
        let text = "class C <: I {}\ninterface I {}"
        answer(db, file, "M", text, [
            MappedSpan(TextRange(0, 7), SpanOrigin.FromSource(TextRange(copied.start, copied.start + 7))),
            MappedSpan(TextRange(7, text.size), SpanOrigin.FromCall)
        ])
        let source = file.text(db).toString()

        // act
        let atUse = hoverAt(db, file.fileId(db), offsetIn(source, "C)"))
        let atItself = hoverAt(db, file.fileId(db), offsetIn(source, "class C", plus: 6))

        // assert
        @Expect(atUse?.items.map {item => hoverText(item)}, Some(["class C <: I in m — a class"]))
        @Expect(atItself?.items.map {item => hoverText(item)}, Some(["class C <: I in m — a class"]))
    }

    @TestCase
    func anEnumConstructorShowsTheDocBeforeItsPipe() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            enum E {
                /** the first */
                | A
                // the second
                | B(Int64)
            }
            let e = E.$0B(1)
            //        ^ B(Int64) in m.E — the second
            "#)
    }

    @TestCase
    func aDeclarationInCallsOfAnyMacroShowsTheDocBeforeThem() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            import m.ms.M
            // a function
            @M
            @M
            func f(): Unit {}
            main() {
                $0f()
            //    ^ func f(): Unit in m — a function
            }
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro M(input: Tokens): Tokens { input }
            "#)
    }

    @TestCase
    func aMacroCallShowsNothingYet() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            import m.ms.M
            @$0M
            // ^ no hover
            func f(): Unit {}
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro M(input: Tokens): Tokens { input }
            "#)
    }
}

@Test
class HoverBinaryTest {
    @TestCase
    func aFunctionOfStdShowsItsSignatureFromItsCjo() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            func f(): Unit {
                $0println("x")
            //    ^^^^^^^ public func println(str: String): Unit in std.core
            }
            "#, std: ["std.core"])
    }

    @TestCase
    func aMemberOfAGenericTypeOfStdAsAMemberOfTheValue() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            import std.collection.ArrayList
            main() {
                let list = ArrayList<String>()
                list.$0add("a")
            //         ^^^ public func add(element: String): Unit in std.collection.ArrayList
            }
            "#, std: ["std.core", "std.collection"])
    }

    @TestCase
    func aDeclarationOfStdShowsItsDocFromItsSourcesWhereTheyAre() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            main() {
                $0sleep(Duration.second)
            //    ^^^^^ public func sleep(dur: Duration): Unit in std.core — Sleep current thread for @p dur interval. / If @p dur is less than or equal to Duration.Zero, current thread will relinquish the run right. /  / @param dur Sleeping duration.
            }
            "#, std: ["std.core"], sources: true)
    }
}

@Test
class BuiltinHoverTest {
    @TestCase
    func aTypeThatIsAKeywordShowsWhatItIs() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            func twice(n: $0Int64): Int64 { n * 2 }
            //              ^^^^^ type Int64 — A 64-bit signed integer, from -2^63 to 2^63-1: the integer type preferred, which an integer literal is where nothing gives it another. A literal of this type is suffixed `i64`: `1i64`.
            "#)
    }

    @TestCase
    func aTypeThatIsAKeywordInABody() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            main() {
                let x = $0Float64(1)
            //            ^^^^^^^ type Float64 — A 64-bit floating-point number, binary64 (IEEE 754), about 15 significant decimal digits. A literal of this type is suffixed `f64`: `1.5f64`.
            }
            "#)
    }

    @TestCase
    func aValueArray() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            func f(a: $0VArray<Int64, $3>): Unit {}
            //          ^^^^^^ type VArray<T, $N> — An array that is a value, of `$N` elements of type `T`, its length an `Int64` literal part of its type: `VArray<Int64, $3>`. Made by `VArray<T, $N>({i => ...})` or `VArray<T, $N>(repeat: v)`; it has `[]` and `size`. An element is no reference type, enum, lambda (but a `CFunc`) or generic type.
            "#)
    }

    @TestCase
    func aTypeOfTheCompilersOwnShowsWhatItIs() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            func f(p: $0CPointer<Int64>): Unit {}
            //          ^^^^^^^^ public type CPointer<T> where T <: CType in std.core — A C pointer to a `T` that is a `CType`: read, written, moved by arithmetic, compared to null and turned into an integer; reading, writing and arithmetic in `unsafe` only.
            "#, std: ["std.core"])
    }

    @TestCase
    func anAnnotationOfTheCompilers() {
        checkHover(#"
            //- /main.cj module=m package=m
              package m
              @$0Frozen
            //   ^^^^^^ @Frozen — The function or property will not change in later versions: neither its signature nor its body, so the same compiler with the same options builds the same code of it. On any function but a local one, and on a property.
              public func f(): Unit {}
            "#)
    }

    @TestCase
    func anAnnotationWithArguments() {
        checkHover(#"
            //- /main.cj module=m package=m
              package m
              @$0When[os == "Linux"]
            //   ^^^^ @When[condition] — Conditional compilation: the import or declaration is compiled only where the condition holds, of `os`, `arch`, `env`, `backend`, `cjc_version`, `debug`, `test` and the variables `--cfg` sets: `@When[os == "Linux" && !debug]`.
              func f(): Unit {}
            "#)
    }

    @TestCase
    func anAnnotationOnALambda() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            main() {
                let add = @$0OverflowWrapping { a: Int64, b: Int64 => a + b }
            //               ^^^^^^^^^^^^^^^^ @OverflowWrapping — An integer operation or conversion in the function that overflows wraps around: the bits beyond the type are dropped.
            }
            "#)
    }

    @TestCase
    func aMacroOfTheCompilers() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            main() {
                let line = @$0sourceLine()
            //                ^^^^^^^^^^ @sourceLine(): Int64 — The line it is written on, as an `Int64` literal.
            }
            "#)
    }

    @TestCase
    func aMacroOfTheWorkspaceNamedAsOneOfTheCompilersIsNotIt() {
        checkHover(#"
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro sourceLine(input: Tokens): Tokens { input }
            //- /main.cj module=m package=m
            package m
            import m.ms.sourceLine
            main() {
                let line = @$0sourceLine()
            //                ^^^^^^^^^^ no hover
            }
            "#)
    }

    /**
     * The names `cjsyntax` takes as an annotation of the compiler's, as its `contextualKind` lists them.
     */
    let parserAnnotations = ["JavaMirror", "JavaImpl", "JavaHasDefault", "ObjCMirror", "ObjCImpl", "ForeignGetterName",
        "ForeignSetterName", "ObjCInit", "ObjCOptional", "ForeignName", "CallingConv", "C", "Attribute", "Intrinsic",
        "OverflowThrowing", "OverflowWrapping", "OverflowSaturating", "When", "FastNative", "Annotation", "ConstSafe",
        "Deprecated", "Frozen", "EnsurePreparedToMock", "NonProduct"]

    @TestCase
    func everyAnnotationOfTheCompilersIsTold() {
        for (name in parserAnnotations) {
            // arrange
            let fixture = Fixture.parse("//- /main.cj module=m package=m\npackage m\n@${name} func f(): Unit {}\n")
            let db = fixture.database()
            let fileId = fixture.file("/main.cj").fileId

            // act
            let hover = hoverAt(db, fileId, "package m\n@".size)

            // assert
            @Expect(builtinAnnotationDoc(name).isSome())
            @Expect(hover.map {one => one.items.map {item => item.code}},
                builtinAnnotationDoc(name).map {doc => [doc.code]})
        }
    }

    @TestCase
    func everyAnnotationToldIsOneOfTheCompilers() {
        // act
        let unknown = BUILTIN_ANNOTATION_DOCS |> filter {doc: BuiltinDoc => !parserAnnotations.contains(doc.name)} |>
            map {doc: BuiltinDoc => doc.name} |> collectArray

        // assert
        @Expect(unknown, Array<String>())
    }

    @TestCase
    func everyTypeThatIsAKeywordToldIsOne() {
        let keywords = ["Int8", "Int16", "Int32", "Int64", "IntNative", "UInt8", "UInt16", "UInt32", "UInt64",
            "UIntNative", "Float16", "Float32", "Float64", "Bool", "Rune", "Unit", "Nothing", "VArray"]
        for (name in keywords) {
            // arrange
            let fixture = Fixture.parse("//- /main.cj module=m package=m\npackage m\ntype A = ${name}\n")
            let db = fixture.database()
            let fileId = fixture.file("/main.cj").fileId

            // act
            let hover = hoverAt(db, fileId, "package m\ntype A = ".size)

            // assert
            @Expect(hover.flatMap {one => one.items.get(0)}.map {item => item.code.startsWith("type ${name}")}, true)
        }
    }
}
