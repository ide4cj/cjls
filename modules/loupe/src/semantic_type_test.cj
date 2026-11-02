package loupe

import std.sync.AtomicBool
import std.unittest.*
import std.unittest.testmacro.*
import calca.CancelledException
import loupe.fixture.*
import loupe.hir.*
import rope.Rope

@Test
class SemanticTypeTest {
    @TestCase
    func nominalArgumentsAndDefinitionsNeedNoDatabase(): Unit {
        // arrange
        let fixture = Fixture.parse("class Box<T> {}\nfunc f(x: Box<Int64>) { x$0 }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()

        // act
        let occurrence = SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow()
        let resolved = occurrence.definitions.getOrThrow()[0].semanticType().getOrThrow()
        let (definition, argument) =
            match (resolved.kind()) {
                case DeclaredType(definition, args) => (definition, args[0])
                case _ => throw FixtureException("expected a nominal type")
            }

        // assert
        @Expect(resolved.display(), "Box<Int64>")
        @Expect(semanticOriginText(definition), ["Box"])
        @Expect(argument.display(), "Int64")
        @Expect(match (argument.kind()) {
            case PrimitiveType(name) => name == "Int64"
            case _ => false
        })

        // act
        db.setFileText(at.fileId, Rope("func f() {}"))

        // assert
        @AssertThrows[CancelledException](resolved.kind())
        @AssertThrows[CancelledException](resolved.display())
        @AssertThrows[CancelledException](argument.kind())
        @AssertThrows[CancelledException](argument.display())
        @AssertThrows[CancelledException](definition.origins())
    }

    @TestCase
    func functionTypesComposeWithTupleAndGenericOrigins(): Unit {
        // arrange
        let fixture = Fixture.parse("func f<T>(callback: (T) -> (T, Bool)) { callback$0 }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()

        // act
        let resolved = SemanticAnalysis(db)
            .at(at.fileId, at.offset)
            .getOrThrow()
            .definitions
            .getOrThrow()[0]
            .semanticType()
            .getOrThrow()
        let (parameter, result, isC) =
            match (resolved.kind()) {
                case FunctionType(params, ret, isC) => (params[0], ret, isC)
                case _ => throw FixtureException("expected a function type")
            }
        let generic =
            match (parameter.kind()) {
                case TypeParameterType(definition) => definition
                case _ => throw FixtureException("expected a generic parameter")
            }

        // assert
        @Expect(!isC)
        @Expect(parameter.display(), "T")
        @Expect(semanticOriginText(generic), ["T"])
        @Expect(match (result.kind()) {
            case TupleType(elements) => elements.size == 2 && elements[0].display() == "T" && elements[1].display() == "Bool"
            case _ => false
        })
    }

    @TestCase
    func compilerOwnedAndFixedArrayTypesKeepTheirStructure(): Unit {
        // arrange
        let fixture = Fixture.parse(
            "type Pointer = CPointer<Int64>\nfunc f(x: (Pointer, VArray<Bool, $2>)) { x$0 }"
        )
        let db = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let at = fixture.cursor.getOrThrow()

        // act
        let resolved = SemanticAnalysis(db)
            .at(at.fileId, at.offset)
            .getOrThrow()
            .definitions
            .getOrThrow()[0]
            .semanticType()
            .getOrThrow()
        let elements =
            match (resolved.kind()) {
                case TupleType(elements) => elements
                case _ => throw FixtureException("expected a tuple type")
            }

        // assert
        @Expect(match (elements[0].kind()) {
            case CompilerOwnedType(head, args) => head == CompilerType.PointerType && args[0].display() == "Int64"
            case _ => false
        })
        @Expect(match (elements[1].kind()) {
            case FixedArrayType(element, size) => size == 2 && element.display() == "Bool"
            case _ => false
        })
    }

    @TestCase
    func invalidAndUnsupportedTypesRemainDistinct(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /main.cj module=m package=m
            package m
            import m.ms.M
            func f() { let bad = absent; let pending = @M(1); bad; pending$0 }
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro M(input: Tokens): Tokens { input }
            "#
        )
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)

        // act
        let invalid = analysis
            .at(at.fileId, fixture.files[0].text.indexOf("bad;").getOrThrow())
            .getOrThrow()
            .definitions
            .getOrThrow()[0]
            .semanticType()
            .getOrThrow()
        let unsupported = analysis
            .at(at.fileId, at.offset)
            .getOrThrow()
            .definitions
            .getOrThrow()[0]
            .semanticType()
            .getOrThrow()

        // assert
        @Expect(invalid.display(), unsupported.display())
        @Expect(match (invalid.kind()) {
            case InvalidType => true
            case _ => false
        })
        @Expect(match (unsupported.kind()) {
            case UnsupportedType(reason) => reason.toString() == "macro call"
            case _ => false
        })
    }

    @TestCase
    func unavailableReasonsRemainStructuredAndInheritRequestCancellation(): Unit {
        // arrange
        let fixture = Fixture.parse("func f() { let x = \"text\"; x$0 }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let stop = AtomicBool(false)
        let analysis = SemanticAnalysis(db.snapshot(cancelledBy: { => stop.load() }))

        // act
        let resolved = analysis
            .at(at.fileId, at.offset)
            .getOrThrow()
            .definitions
            .getOrThrow()[0]
            .semanticType()
            .getOrThrow()

        // assert
        @Expect(resolved.display(), "{unknown}")
        @Expect(match (resolved.kind()) {
            case UnavailableType(reason) => reason == UnknownReason.NoStd
            case _ => false
        })

        // act
        stop.store(true)

        // assert
        @AssertThrows[CancelledException](resolved.kind())
        @AssertThrows[CancelledException](resolved.display())
    }
}
