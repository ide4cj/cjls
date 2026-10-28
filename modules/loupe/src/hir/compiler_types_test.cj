package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*

@Test
class CompilerTypesTest {
    @TestCase
    func sourceCoreResolvesPointersAndTheirGenericMembers() {
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
    func signaturesUseSemanticHeadsAndKeepTypeErrors() {
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
        @Expect(signatureTypes(db, good).params, [pointer,
            Ty(db, BuiltInTy(CStringType, [])),
            Ty(db, BuiltInTy(RawArrayType, [pointer])),
            Ty(db, FuncTy([byte], Ty(db, PrimTy("Unit")), true)),
            Ty(db, VArrayTy(byte, 2))])
        let pkg = PackageRef.Source(packageOfFile(db, file).getOrThrow())
        let typo = signatureTypes(db, exportOf(db, pkg, "typo"))
        @Expect(typo.errors.map { error => error.kind }, [TyErrorKind.UndeclaredType("CPinter")])
        let missing = signatureTypes(db, exportOf(db, pkg, "missing"))
        @Expect(missing.errors.map { error => error.kind },
            [TyErrorKind.NeedsTypeArgs, TyErrorKind.WrongTypeArgCount])
    }

    @TestCase
    func binaryAndSourceBuiltinsHaveTheSameHeads() {
        let (db, core) = stdPackage("std.core")
        for (
            entry in [
                ("CPointer", PointerType),
                ("CString", CStringType),
                ("RawArray", RawArrayType)
            ]
        ) {
            let id = exportOf(db, core, entry[0])
            let args = Array(genericsOf(db, id).size) { i => Ty(db, ParamTy(id, i)) }
            @Expect(signatureTypes(db, id).ty, Some(Ty(db, BuiltInTy(entry[1], args))))
        }
        @Expect(packageExtends(db, core).contains(ExtendedType.BuiltInHead(PointerType)))
        @Expect(packageExtends(db, core).contains(ExtendedType.BuiltInHead(CStringType)))
    }

    @TestCase
    func builtinVisibilityAndTyposUseOrdinaryScopeRules() {
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
        let core = db.sourceFile(fixture.files[0].fileId).getOrThrow()
        let user = db.sourceFile(fixture.files[1].fileId).getOrThrow()
        let corePkg = packageOfFile(db, core).getOrThrow()
        let userPkg = packageOfFile(db, user).getOrThrow()
        for (name in ["CPointer", "CString", "RawArray", "CFunc", "VArray"]) {
            @Expect(match (lookUp(db, corePkg, core, name, Namespace.Types)) { case Found(_) => true; case _ => false })
        }
        for (name in ["CPointer", "CString", "CFunc", "VArray"]) {
            @Expect(match (lookUp(db, userPkg, user, name, Namespace.Types)) { case Found(_) => true; case _ => false })
        }
        @Expect(lookUp(db, userPkg, user, "RawArray", Namespace.Types), Resolution.NotFound)
        @Expect(lookUp(db, corePkg, core, "CPinter", Namespace.Types), Resolution.NotFound)
    }
}
