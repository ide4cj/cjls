package loupe

import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange
import loupe.db.{MappedSpan, SpanOrigin}
import loupe.fixture.*

@Test
class HoverCallTest {
    @TestCase[explicit in [false, true]]
    func successfulCallsShowTheirFinalTypeArguments(explicit: Bool): Unit {
        // arrange
        let application = if (explicit) { "identity<Bool>(true)" } else { "identity(true)" }
        let fixture = Fixture.parse(
            """
            //- /main.cj module=m package=m
            package m
            func identity<T>(value: T): T { value }
            func f() { ${application} }
            """
        )
        let db = fixture.database()
        let file = fixture.files[0]
        let offset = file.text.indexOf(application).getOrThrow()

        // act
        let result = hoverAt(db, file.fileId, offset).getOrThrow()

        // assert
        @Assert(result.items.size, 1)
        @Expect(result.items[0].code, "func identity<Bool>(value: Bool): Bool")
        @Expect(result.items[0].path, Some("m"))
        @Expect(result.range, TextRange(offset, offset + "identity".size))
    }

    @TestCase
    func callSignaturesPreserveDocumentationPathAndUtf8Ranges(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /main.cj module=m package=m
            package m
            /** Keeps `value`. */
            public func identity<T>(value: T): T { value }
            func f() { let число = 1; ident$0ity(число) }
            "#
        )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let file = fixture.files[0]
        let start = file.text.indexOf("identity(число)").getOrThrow()

        // act
        let call = hoverAt(db, cursor.fileId, cursor.offset).getOrThrow()
        let declaration = hoverAt(db, file.fileId, file.text.indexOf("identity<T>").getOrThrow())
            .getOrThrow()

        // assert
        @Assert(call.items.size, 1)
        @Expect(call.items[0].code, "public func identity<Int64>(value: Int64): Int64")
        @Expect(call.items[0].doc, Some("Keeps `value`."))
        @Expect(call.items[0].path, Some("m"))
        @Expect(call.range, TextRange(start, start + "identity".size))
        @Expect(declaration.items[0].code, "public func identity<T>(value: T): T")
        @Expect(declaration.items[0].doc, call.items[0].doc)
        @Expect(declaration.items[0].path, call.items[0].path)
    }

    @TestCase
    func receiverAndMethodBindersSubstituteIndependently(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /main.cj module=m package=m
            package m
            class Box<T> {
                public func pair<U>(left: T, right!: U): (T, U) { (left, right) }
            }
            func f(box: Box<Int64>) { box.pa$0ir(1, right: true) }
            "#
        )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()

        // act
        let result = hoverAt(db, cursor.fileId, cursor.offset).getOrThrow()

        // assert
        @Assert(result.items.size, 1)
        @Expect(result.items[0].code, "public func pair<Bool>(left: Int64, right!: Bool): (Int64, Bool)")
        @Expect(result.items[0].path, Some("m.Box"))
    }

    @TestCase
    func sameNamedReceiverAndMethodGenericsKeepTheirOwnBinders(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /main.cj module=m package=m
            package m
            class Box<T> {
                public func echo<T>(value: T): T { value }
            }
            func f(box: Box<Int64>) { box.ec$0ho(true) }
            "#
        )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()

        // act
        let result = hoverAt(db, cursor.fileId, cursor.offset).getOrThrow()

        // assert
        @Assert(result.items.size, 1)
        @Expect(result.items[0].code, "public func echo<Bool>(value: Bool): Bool")
        @Expect(result.items[0].path, Some("m.Box"))
    }

    @TestCase[explicit in [false, true]]
    func localGenericCallsRetainCapturedOwnerParameters(explicit: Bool): Unit {
        // arrange
        let application = if (explicit) { "local<Bool>(true)" } else { "local(true)" }
        let fixture = Fixture.parse(
            """
            //- /main.cj module=m package=m
            package m
            func outer<A>(captured: A) {
                func local<T>(value: T): (A, T) { (captured, value) }
                ${application}
            }
            """
        )
        let db = fixture.database()
        let file = fixture.files[0]
        let offset = file.text.indexOf(application).getOrThrow()

        // act
        let call = hoverAt(db, file.fileId, offset).getOrThrow()
        let declaration = hoverAt(db, file.fileId, file.text.indexOf("local<T>").getOrThrow())
            .getOrThrow()

        // assert
        @Assert(call.items.size, 1)
        @Expect(call.items[0].code, "func local<Bool>(value: Bool): (A, Bool)")
        @Expect(call.items[0].path.isNone())
        @Expect(declaration.items[0].code, "func local<T>(value: T): (A, T)")
    }

    @TestCase
    func failedCallsKeepTheirDeclaredGenericSignature(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /main.cj module=m package=m
            package m
            func identity<T>(value: T): T { value }
            func f() { ident$0ity<Bool>(1) }
            "#
        )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()

        // act
        let result = hoverAt(db, cursor.fileId, cursor.offset).getOrThrow()

        // assert
        @Assert(result.items.size, 1)
        @Expect(result.items[0].code, "func identity<T>(value: T): T")
    }

    @TestCase
    func ambiguousAndMissingCallsKeepTheirExistingFallbacks(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /main.cj module=m package=m
            package m
            func choose(value: Int8): Int8 { value }
            func choose(value: Int16): Int16 { value }
            func f() { cho$0ose(1); missing() }
            "#
        )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let file = fixture.files[0]

        // act
        let ambiguous = hoverAt(db, cursor.fileId, cursor.offset).getOrThrow()
        let missing = hoverAt(db, file.fileId, file.text.indexOf("missing()").getOrThrow())

        // assert
        @Expect(ambiguous.items.map { item => item.code }, [
            "func choose(value: Int8): Int8",
            "func choose(value: Int16): Int16"
        ])
        @Expect(missing.isNone())
    }

    @TestCase[explicit in [false, true]]
    func constructorsKeepTheNamedTypeHover(explicit: Bool): Unit {
        // arrange
        let application = if (explicit) { "Box<Int64>(1)" } else { "Box(1)" }
        let fixture = Fixture.parse(
            """
            //- /main.cj module=m package=m
            package m
            /** A box. */
            class Box<T> { init(value: T) {} }
            func f() { ${application} }
            """
        )
        let db = fixture.database()
        let file = fixture.files[0]
        let offset = file.text.indexOf(application).getOrThrow()

        // act
        let result = hoverAt(db, file.fileId, offset).getOrThrow()

        // assert
        @Assert(result.items.size, 1)
        @Expect(result.items[0].code, "class Box<T>")
        @Expect(result.items[0].path, Some("m"))
        @Expect(result.items[0].doc, Some("A box."))
        @Expect(result.range, TextRange(offset, offset + "Box".size))
    }
    @TestCase
    func overloadedOperatorsUseTheirSelectedConcreteSignature(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /main.cj module=m package=m
            package m
            struct Counter {
                operator func +<T>(right: T): T { right }
            }
            func f(counter: Counter) { counter +$0 true }
            "#
        )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()

        // act
        let result = hoverAt(db, cursor.fileId, cursor.offset).getOrThrow()

        // assert
        @Assert(result.items.size, 1)
        @Expect(result.items[0].code, "operator func +<Bool>(right: Bool): Bool")
        @Expect(result.items[0].path, Some("m.Counter"))
    }

    @TestCase
    func successfulCallsOmitBoundsWhileDeclarationsRetainThem(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /main.cj module=m package=m
            package m
            interface I {}
            class C <: I {}
            func keep<T>(value: T): T where T <: I { value }
            func f() { ke$0ep(C()) }
            "#
        )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let file = fixture.files[0]

        // act
        let call = hoverAt(db, cursor.fileId, cursor.offset).getOrThrow()
        let declaration = hoverAt(db, file.fileId, file.text.indexOf("keep<T>").getOrThrow())
            .getOrThrow()

        // assert
        @Assert(call.items.size, 1)
        @Expect(call.items[0].code, "func keep<C>(value: C): C")
        @Expect(declaration.items[0].code, "func keep<T>(value: T): T where T <: I")
    }

    @TestCase
    func chainedApplicationsShowTheSharedFinalGenericSolution(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /main.cj module=m package=m
            package m
            func factory<T>(): (T) -> (T) -> T { { x => { y => y } } }
            func f() { fact$0ory()(1)(2) }
            "#
        )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()

        // act
        let result = hoverAt(db, cursor.fileId, cursor.offset).getOrThrow()

        // assert
        @Assert(result.items.size, 1)
        @Expect(result.items[0].code, "func factory<Int64>(): (Int64) -> (Int64) -> Int64")
        @Expect(result.items[0].path, Some("m"))
    }

    @TestCase
    func binaryGenericMethodsUseConcreteTypesWithoutSourceAttachments(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /main.cj module=m package=m
            package m
            func f(values: Array<Int64>) { values.ma$0p { value => true } }
            "#
        )
        let db = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let cursor = fixture.cursor.getOrThrow()

        // act
        let result = hoverAt(db, cursor.fileId, cursor.offset).getOrThrow()

        // assert
        @Assert(result.items.size, 1)
        @Expect(result.items[0].code, "public func map<Bool>(transform: (Int64) -> Bool): Array<Bool>")
        @Expect(result.items[0].path, Some("std.core.Array"))
        @Expect(result.items[0].doc.isNone())
    }

    @TestCase
    func expressionExpansionsRetainTheirConcreteSignatureAndExactRange(): Unit {
        // arrange
        let (db, file) = expansionDatabase(
            #"
            package m
            import m.ms.*
            /** Keeps `value`. */
            public func identity<T>(value: T): T { value }
            func f() { @A(1) }
            "#
        )
        const OUTPUT = "identity(1)"
        let call = answer(
            db,
            file,
            "A",
            OUTPUT,
            [MappedSpan(TextRange(0, OUTPUT.size), SpanOrigin.FromCall)]
        )

        // act
        let result = hoverInExpansion(db, call, 2).getOrThrow()

        // assert
        @Assert(result.items.size, 1)
        @Expect(result.items[0].code, "public func identity<Int64>(value: Int64): Int64")
        @Expect(result.items[0].path, Some("m"))
        @Expect(result.items[0].doc, Some("Keeps `value`."))
        @Expect(result.range, TextRange(0, "identity".size))
    }

    @TestCase
    func functionValuesAndCallableObjectsKeepTheirVariableHover(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /main.cj module=m package=m
            package m
            struct Callable {
                operator func ()<T>(value: T): T { value }
            }
            func f() {
                let callback: (Int64) -> Int64 = { value => value }
                call$0back(1)
                let callable = Callable()
                callable(true)
            }
            "#
        )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let file = fixture.files[0]
        let objectOffset = file.text.indexOf("callable(true)").getOrThrow()

        // act
        let functionValue = hoverAt(db, cursor.fileId, cursor.offset).getOrThrow()
        let callableObject = hoverAt(db, file.fileId, objectOffset).getOrThrow()

        // assert
        @Assert(functionValue.items.size, 1)
        @Expect(functionValue.items[0].code, "let callback: (Int64) -> Int64")
        @Assert(callableObject.items.size, 1)
        @Expect(callableObject.items[0].code, "let callable: Callable")
    }
}
