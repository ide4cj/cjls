package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.{Fixture, FixtureException}
import rope.Rope

@Test
class CompilerTypesTest {
    @TestCase
    func nullPointerConstructorsHaveTheirSemanticType(): Unit {
        checkInference(
            #"
            import std.core as native
            type Pointer<T> = CPointer<T>
            func test(): Unit {
                let pointer = CPointer<Unit>()
            //      ^^^^^^^ CPointer<Unit>
                let byte = native.CPointer<Int8>()
            //      ^^^^ CPointer<Int8>
                let alias = Pointer<Int32>()
            //      ^^^^^ CPointer<Int32>
                let inferred: CPointer<Int8> = CPointer()
            //      ^^^^^^^^ CPointer<Int8>
                let chained = CPointer<Unit>().isNull()
            //      ^^^^^^^ Bool
            }
            func make<T>(): CPointer<T> where T <: CType {
                let generic = CPointer<T>()
            //      ^^^^^^^ CPointer<T>
                generic
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func sourceCoreProvidesTheNullConstructor(): Unit {
        checkInference(
            #"
            //- /std/core/core.cj module=std package=std.core
            package std.core
            public interface CType {}
            //- /app/main.cj module=app deps=std package=app
            package app
            type Pointer = CPointer<Unit>
            func test(): Unit {
                let pointer = CPointer<Unit>()
            //      ^^^^^^^ CPointer<Unit>
                let alias = Pointer()
            //      ^^^^^ CPointer<Unit>
            }
            "#,
            binaries: []
        )
    }

    @TestCase
    func sourceCoreResolvesPointersAndTheirGenericMembers(): Unit {
        checkInference(
            #"
            //- /std/core/core.cj module=std package=std.core
            package std.core
            public interface CType {}
            extend Int8 <: CType {}
            extend<T> CPointer<T> where T <: CType {
                public func read(): T { throw Exception() }
                public func next(): CPointer<T> { this }
                public static func make(): CPointer<T> { throw Exception() }
            }
            public struct Array<T> where T <: CType {
                public let rawptr: RawArray<T>
                public func pointer(): CPointer<T> { throw Exception() }
            }
            func identity<T>(p: CPointer<T>): CPointer<T> where T <: CType { p }
            //               ^ CPointer<T>
            func use(a: Array<Int8>, p: CPointer<Int8>): Unit {
            //       ^ Array<Int8>
            //                       ^ CPointer<Int8>
                let x = p.read()
            //      ^ Int8
                let y = p.next()
            //      ^ CPointer<Int8>
                let z = a.pointer().read()
            //      ^ Int8
                let q = CPointer<Int8>.make()
            //      ^ CPointer<Int8>
                let raw = a.rawptr
            //      ^^^ RawArray<Int8>
                let same = identity(p)
            //      ^^^^ CPointer<Int8>
            }
            "#,
            binaries: []
        )
    }

    @TestCase
    func signaturesUseSemanticHeadsAndKeepTypeErrors(): Unit {
        // arrange
        let (db, file, good) =
            declOf(
                #"
            //- /std/core/core.cj module=std package=std.core
            package std.core
            public interface CType {}
            func good(p: CPointer<Int8>, s: CString, raw: RawArray<CPointer<Int8>>,
                cb: CFunc<(Int8) -> Unit>, fixed: VArray<Int8, $2>): Unit {}
            func typo(p: CPinter<Int8>): Unit {}
            func missing(p: CPointer, cb: CFunc): Unit {}
            "#,
                "good"
            )
        let byte = Ty(db, PrimTy("Int8"))
        let pointer = Ty(db, BuiltInTy(PointerType, [byte]))

        // act
        let goodSignature = signatureTypes(db, good)
        let pkg =
            PackageRef
                .Source(
                    packageOfFile(db, file)
                        .getOrThrow { FixtureException("good must belong to std.core") }
                )
        let typo = signatureTypes(db, exportOf(db, pkg, "typo"))
        let missing = signatureTypes(db, exportOf(db, pkg, "missing"))

        // assert
        @Expect(goodSignature.params, [pointer,
            Ty(db, BuiltInTy(CStringType, [])),
            Ty(db, BuiltInTy(RawArrayType, [pointer])),
            Ty(db, FuncTy([byte], Ty(db, PrimTy("Unit")), true)),
            Ty(db, VArrayTy(byte, 2))])
        @Expect(typo.errors.map { error => error.kind }, [TyErrorKind.UndeclaredType("CPinter")])
        @Expect(missing.errors.map { error => error.kind },
            [TyErrorKind.NeedsTypeArgs, TyErrorKind.WrongTypeArgCount])
    }

    @TestCase
    func binaryAndSourceBuiltinsHaveTheSameHeads(): Unit {
        // arrange
        let (db, core) = stdPackage("std.core")
        for (
            entry in [
                ("CPointer", PointerType),
                ("CString", CStringType),
                ("RawArray", RawArrayType)
            ]
        ) {
            let id = exportOf(db, core, entry[0])
            let args =
                Array(genericsOf(db, id).size) {
                    i =>
                    Ty(db, ParamTy(GenericOwner.Declaration(id), i))
                }

            // act
            let signature = signatureTypes(db, id)

            // assert
            @Expect(signature.ty, Some(Ty(db, BuiltInTy(entry[1], args))))
        }

        // act
        let extensions = packageExtends(db, core)

        // assert
        @Expect(extensions.contains(ExtendedType.BuiltInHead(PointerType)))
        @Expect(extensions.contains(ExtendedType.BuiltInHead(CStringType)))
    }

    @TestCase
    func invalidBuiltinSupertypeCyclesStopAfterEachHead(): Unit {
        // arrange
        let (db, file, _) =
            declOf(
                #"
            //- /std/core/core.cj module=std package=std.core
            package std.core
            public interface CType {}
            extend<T> CPointer<T> <: CPointer<CPointer<T>> {}
            func anchor(): Unit {}
            "#,
                "anchor"
            )
        let pointer = Ty(db, BuiltInTy(PointerType, [Ty(db, PrimTy("Int8"))]))

        // act: invalid editor input must not expand a fresh pointer at every step.
        let supertypes = allSupertypes(db, pointer, file)

        // assert
        @Expect(supertypes,
            [pointer, Ty(db, BuiltInTy(PointerType, [pointer]))])
    }

    @TestCase
    func builtinVisibilityAndTyposUseOrdinaryScopeRules(): Unit {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            //- /std/core/core.cj module=std package=std.core
            package std.core
            public interface CType {}
            //- /app/main.cj module=app deps=std package=app
            package app
            "#
                )
        let db = fixture.database()
        let core =
            db
                .sourceFile(fixture.files[0].fileId)
                .getOrThrow { FixtureException("fixture must contain std.core") }
        let user =
            db
                .sourceFile(fixture.files[1].fileId)
                .getOrThrow { FixtureException("fixture must contain app") }
        let corePkg =
            packageOfFile(db, core).getOrThrow { FixtureException("core must belong to std.core") }
        let userPkg =
            packageOfFile(db, user).getOrThrow { FixtureException("user must belong to app") }
        for (name in ["CPointer", "CString", "RawArray", "CFunc", "VArray"]) {
            // act
            let found = lookUp(db, corePkg, core, name, Namespace.Types)

            // assert
            @Expect(match (found) { case Found(_) => true; case _ => false })
        }
        for (name in ["CPointer", "CString", "CFunc", "VArray"]) {
            // act
            let found = lookUp(db, userPkg, user, name, Namespace.Types)

            // assert
            @Expect(match (found) { case Found(_) => true; case _ => false })
        }

        // act
        let hidden = lookUp(db, userPkg, user, "RawArray", Namespace.Types)
        let typo = lookUp(db, corePkg, core, "CPinter", Namespace.Types)

        // assert
        @Expect(hidden, Resolution.NotFound)
        @Expect(typo, Resolution.NotFound)

        // act
        db.setFileText(user.fileId(db), Rope("package app\npublic struct CPointer<T> {}"))
        let shadow = lookUp(db, userPkg, user, "CPointer", Namespace.Types)

        // assert
        match (shadow) {
            case Found(ids) => @Expect(ids[0].item(db).kind, ItemKind.Struct)
            case _ => @Expect(false)
        }
    }
}
