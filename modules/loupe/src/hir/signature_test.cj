package loupe.hir

import std.collection.*
import std.sync.AtomicInt64
import std.unittest.*
import std.unittest.testmacro.*
import calca.*
import calca.macros.*
import rope.Rope
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.fixture.*

/**
 * The signature of each item of the fixture's only file and of their members, one line each, as
 * `kind name: generics (params) -> ty <: supers where bounds`, what is empty left out.
 */
func signaturesOf(fixture: String): Array<String> {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database()
    let source = db.sourceFile(parsed.files[0].fileId).getOrThrow()
    let lines = ArrayList<String>()
    func render(items: Array<Item>): Unit {
        for (item in items) {
            let sig = signature(db, DefId(db, ItemFile.Source(source), item.id))
            let list = {ids: Array<TypeRefId> => String.join(ids.map {id => sig.text(id)}, delimiter: ", ")}
            let line = StringBuilder("${item.kind} ${item.names.get(0) ?? "_"}:")
            if (!sig.generics.isEmpty()) {
                line.append(" <${String.join(sig.generics, delimiter: ", ")}>")
            }
            if (!sig.params.isEmpty()) {
                line.append(" (${list(sig.params)})")
            }
            if (let Some(ty) <- sig.ty) {
                line.append(" -> ${sig.text(ty)}")
            }
            if (!sig.supers.isEmpty()) {
                line.append(" <: ${list(sig.supers)}")
            }
            for (bound in sig.bounds) {
                line.append(" where ${sig.text(bound.ty)} <: ${list(bound.bounds)}")
            }
            lines.add(line.toString())
            render(item.members)
        }
    }
    render(itemTree(db, source).items)
    lines.toArray()
}

let signatureReaderRuns = AtomicInt64(0)

/**
 * A query reading a declaration's signature, as resolution will; it counts its runs.
 */
@CalcaTracked
func paramCount(db: AnalysisDatabase, def: DefId): Int64 {
    signatureReaderRuns.fetchAdd(1)
    signature(db, def).params.size
}

@Test
class SignatureTest {
    @TestCase
    func aFunctionHasItsTypeParametersParametersReturnTypeAndBounds() {
        @Expect(signaturesOf(#"
            package m
            func f<T, U>(x: a.C<T>, y!: ?U = None, z: (Int64, Bool) -> Unit): VArray<T, $3> where T <: I<U> & J {}
            "#), ["Func f: <T, U> (a.C<T>, ?U, (Int64, Bool) -> Unit) -> VArray<T, $3> where T <: I<U>, J"])
    }

    @TestCase
    func aTypeHasItsSupertypesAndItsMembersTheirOwn() {
        @Expect(signaturesOf(#"
            package m
            class A<T> <: I<T> & J where T <: ToString {
                var v: ?T = None
                prop p: T { get() { v.getOrThrow() } }
                init(x: T) { v = x }
                func g<U>(): This { this }
                static func s(): Unit {}
            }
            "#), [
            "Class A: <T> <: I<T>, J where T <: ToString",
            "Var v: -> ?T",
            "Prop p: -> T",
            "Init init: (T)",
            "Func g: <U> -> This",
            "Func s: -> Unit"
        ])
    }

    @TestCase
    func anEnumsConstructorsHaveTheirParameters() {
        @Expect(signaturesOf(#"
            package m
            enum E<T> { | A(T) | B(E<T>, (x: Int64, y: T)) | C }
            "#), ["Enum E: <T>", "EnumCtor A: (T)", "EnumCtor B: (E<T>, (Int64, T))", "EnumCtor C:"])
    }

    @TestCase
    func anExtendAndAnAliasHaveTheTypeTheyName() {
        @Expect(signaturesOf(#"
            package m
            extend<T> Array<T> <: I where T <: J {}
            type L<T> = ArrayList<(T)>
            "#), ["Extend _: <T> -> Array<T> <: I where T <: J", "TypeAlias L: <T> -> ArrayList<T>"])
    }

    @TestCase
    func aTypeNotWrittenIsMissingAndAVariableWithoutOneHasNone() {
        @Expect(signaturesOf(#"
            package m
            func f(x, y: Int64) {}
            let v = 1
            "#), ["Func f: (_, Int64)", "Var v:"])
    }

    @TestCase
    func anEditOfABodyLeavesTheSignatureAndWhatReadItAlone() {
        // arrange
        let parsed = Fixture.parse(#"
            package m
            func f(x: Int64): Int64 { x }
            "#)
        let db = parsed.database()
        let fileId = parsed.files[0].fileId
        let source = db.sourceFile(fileId).getOrThrow()
        let def = DefId(db, ItemFile.Source(source), itemTree(db, source).items[0].id)
        paramCount(db, def)
        let before = signatureReaderRuns.load()
        // act
        db.setFileText(fileId, Rope("package m\n\n// moved\nfunc f(x: Int64): Int64 { x + 1 }\n"))
        paramCount(db, def)
        // assert
        @Expect(signatureReaderRuns.load(), before)
        @Expect(signatureWithSourceMap(db, def).sourceMap.ptrs.size, 2)
    }

    @TestCase
    func anEditOfATypeRunsAgainWhatReadTheSignature() {
        // arrange
        let parsed = Fixture.parse(#"
            package m
            func f(x: Int64): Int64 { x }
            "#)
        let db = parsed.database()
        let fileId = parsed.files[0].fileId
        let source = db.sourceFile(fileId).getOrThrow()
        let def = DefId(db, ItemFile.Source(source), itemTree(db, source).items[0].id)
        paramCount(db, def)
        let before = signatureReaderRuns.load()
        // act
        db.setFileText(fileId, Rope("package m\nfunc f(x: Int64, y: Bool): Int64 { x }\n"))
        // assert
        @Expect(paramCount(db, def), 2)
        @Expect(signatureReaderRuns.load(), before + 1)
    }

    @TestCase
    func aDeclarationOfACompiledPackageHasAnEmptySignatureAndNoTypeScope() {
        // arrange
        let db = AnalysisDatabase()
        let bytes = stdCjo("std.core")
        let pkg = binaryPackage(db, "std.core", bytes)
        let file = ItemFile.Binary(pkg, fileIndex(bytes, "std.core/string.cj"))
        let string = DefId(db, file, named(itemTreeOf(db, file).items, "String").id)
        // act
        let lowered = signatureWithSourceMap(db, string)
        // assert
        @Expect(lowered, LoweredSignature(Signature(), SignatureSourceMap([])))
        @Expect(typeScopeOf(db, string).isNone())
    }
}
