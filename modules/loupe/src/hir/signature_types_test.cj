package loupe.hir

import std.collection.*
import std.sync.AtomicInt64
import std.unittest.*
import std.unittest.testmacro.*
import calca.*
import calca.macros.*
import cjsyntax.CjSyntaxNode
import cjsyntax.ast.AnyHasName
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.fixture.*
import loupe.syntax.parse
import loupe.vfs.CjoFileRead
import rope.Rope

/**
 * Checks the signatures of the declarations of `fixture`, as types, are its annotations: `//^ (T)
 * -> Unit` under the name of each (an `extend`'s type), `//^^^ error: message` under a type
 * that is an error. `std.core` is a package of the project, as `?T` needs it.
 */
func checkSignatureTypes(fixture: String): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
    let actual = ArrayList<Annotation>()
    for (file in parsed.files) {
        let source = db.sourceFile(file.fileId).getOrThrow()
        let root = parse(db, source).syntaxNode()
        for (item in itemTree(db, source).items) {
            annotate(db, source, root, item, actual)
        }
    }
    expectAnnotations(fixture, actual.toArray())
}

/**
 * Adds the annotations of `item` and of its members to `actual`.
 */
func annotate(db: AnalysisDatabase, source: SourceFile, root: CjSyntaxNode, item: Item, actual: ArrayList<Annotation>): Unit {
    if (item.kind == ItemKind.Import || item.kind == ItemKind.MacroCall) {
        return
    }
    let fileId = source.fileId(db)
    let def = DefId(db, ItemFile.Source(source), item.id)
    let types = signatureTypes(db, def)
    let lowered = signatureWithSourceMap(db, def)
    let ptrs = lowered.sourceMap.ptrs
    // an `extend` has no name: the type it extends stands for it
    let extended = lowered.signature.ty.flatMap {ty => ptrs.get(ty.index)}.flatMap {ptr => ptr}.flatMap {
        ptr => ptr.tryToNode(root)
    }.map {node => node.textRange}
    if (let Some(node) <- itemIdMap(db, source).node(item.id, root)) {
        let name = AnyHasName.cast(node).flatMap {it => it.name()}.map {it => it.syntax.textRange}
        let range = if (item.kind == ItemKind.Extend) {
            extended
        } else {
            name
        } ?? node.firstToken().getOrThrow().textRange
        actual.add(Annotation(fileId, range, types.text(db, item.kind)))
    }
    for (error in types.errors) {
        if (let Some(Some(ptr)) <- ptrs.get(error.at.index) && let Some(node) <- ptr.tryToNode(root)) {
            actual.add(Annotation(fileId, node.textRange, "error: ${error.message()}"))
        }
    }
    for (member in item.members) {
        annotate(db, source, root, member, actual)
    }
}

let signatureTypesReaderRuns = AtomicInt64(0)

/**
 * A query reading a declaration's signature as types, as inference will; it counts its runs.
 */
@CalcaTracked
func paramTyCount(db: AnalysisDatabase, def: DefId): Int64 {
    signatureTypesReaderRuns.fetchAdd(1)
    signatureTypes(db, def).params.size
}

/**
 * The declarations of a signature as types (step 8a of #48, D54): its paths resolved, its aliases
 * expanded, `?T` std's `Option`; what is an error, as cjc says it. Each case compiled with cjc
 * 1.3.0-alpha.20260918 first: one of no `error` compiles.
 */
@Test
class SignatureTypesTest {
    @TestCase
    func aFunctionOfTypesOfTheLanguage() {
        checkSignatureTypes(#"
            package m
            func f(a: Int64, b: (Bool, Rune), c: (Int64) -> Unit): Float64 { 1.0 }
            //   ^ (Int64, (Bool, Rune), (Int64) -> Unit) -> Float64
            "#)
    }

    @TestCase
    func typesOfThePackageAndTheirArguments() {
        checkSignatureTypes(#"
            package m
            class C<T> {}
            //    ^ C<T> <: Object
            struct S {}
            //     ^ S
            func f(a: C<S>, b: C<C<Int64>>): Unit {}
            //   ^ (C<S>, C<C<Int64>>) -> Unit
            "#)
    }

    @TestCase
    func aTypeOfAnotherPackageByItsQualifier() {
        checkSignatureTypes(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C<T> {}
            //           ^ C<T> <: Object
            //- /main.cj module=m package=m
            package m
            import m.a
            func f(x: a.C<Int64>): Unit {}
            //   ^ (C<Int64>) -> Unit
            "#)
    }

    @TestCase
    func anOptionTypeIsStdCoresOption() {
        // N58
        checkSignatureTypes(#"
            package m
            func f(a: ?Int64, b: ??String): Unit {}
            //   ^ (Option<Int64>, Option<Option<String>>) -> Unit
            "#)
    }

    @TestCase
    func aTypeItsSupertypesAndItsBounds() {
        checkSignatureTypes(#"
            package m
            interface I<T> {}
            //        ^ I<T>
            interface J {}
            //        ^ J
            open class C<T> <: I<T> & J where T <: J {}
            //         ^ C<T> <: Object & I<T> & J where T <: J
            "#)
    }

    @TestCase
    func theMembersOfAGenericType() {
        checkSignatureTypes(#"
            package m
            class C<T> {
            //    ^ C<T> <: Object
                var x: T
            //      ^ T
                init(x: T) {
            //  ^^^^ (T) -> C<T>
                    this.x = x
                }
                func pair<U>(u: U): (T, U) {
            //       ^^^^ <U>(U) -> (T, U)
                    (x, u)
                }
                prop p: Array<T> {
            //       ^ Array<T>
                    get() {
                        [x]
                    }
                }
            }
            "#)
    }

    @TestCase
    func theConstructorsOfAnEnum() {
        checkSignatureTypes(#"
            package m
            enum E<T> {
            //   ^ E<T>
                | A(T, Int64)
            //    ^ (T, Int64) -> E<T>
                | B
            //    ^ E<T>
            }
            "#)
    }

    @TestCase
    func anExtendItsTypeAndItsInterfaces() {
        checkSignatureTypes(#"
            package m
            interface I {}
            //        ^ I
            class C<T> {}
            //    ^ C<T> <: Object
            extend<T> C<T> <: I {}
            //        ^^^^ <T> C<T> <: I
            "#)
    }

    @TestCase
    func aTypeNotWrittenIsInferences() {
        checkSignatureTypes(#"
            package m
            let x = 1
            //  ^ _
            func f() {
            //   ^ () -> _
                1
            }
            "#)
    }

    @TestCase
    func typesWhoseSupertypesNameEachOtherAreNoCycle() {
        // A24
        checkSignatureTypes(#"
            package m
            interface I<T> {}
            //        ^ I<T>
            class A <: I<B> {}
            //    ^ A <: Object & I<B>
            class B <: I<A> {}
            //    ^ B <: Object & I<A>
            "#)
    }

    @TestCase
    func anAliasIsExpandedItsArgumentsSubstituted() {
        checkSignatureTypes(#"
            package m
            type P<T> = (T, T)
            //   ^ <T> = (T, T)
            func f(p: P<Int64>): P<Bool> {
            //   ^ ((Int64, Int64)) -> (Bool, Bool)
                (true, false)
            }
            "#)
    }

    @TestCase
    func anAliasOfAnAlias() {
        checkSignatureTypes(#"
            package m
            type A<T> = Array<T>
            //   ^ <T> = Array<T>
            type B = A<Int64>
            //   ^ = Array<Int64>
            func f(b: B): Unit {}
            //   ^ (Array<Int64>) -> Unit
            "#)
    }

    @TestCase
    func anAliasOfAParameterItDoesNotUse() {
        // cjc warns "type arg(s) Generics-T are not used"
        checkSignatureTypes(#"
            package m
            type U<T> = Int64
            //   ^ <T> = Int64
            func f(a: U<String>): Unit {}
            //   ^ (Int64) -> Unit
            "#)
    }

    @TestCase
    func anAliasOfStdCore() {
        checkSignatureTypes(#"
            package m
            func f(b: Byte): UInt {
            //   ^ (UInt8) -> UInt64
                0
            }
            "#)
    }

    @TestCase
    func aCycleOfAliases() {
        // N92
        checkSignatureTypes(#"
            package m
            type X = Y
            //   ^ = {unknown}
            //       ^ error: type cycle detected: 'X->Y->X'
            type Y = X
            //   ^ = {unknown}
            //       ^ error: type cycle detected: 'Y->X->Y'
            func f(x: X): Unit {}
            //   ^ ({unknown}) -> Unit
            "#)
    }

    @TestCase
    func aCycleIsNamedPastTheAliasesOffIt() {
        // N92: `Byte` and `W` lead nowhere, the search goes on to `Y`
        checkSignatureTypes(#"
            package m
            type W = Int64
            //   ^ = Int64
            type X = (Byte, W, Y)
            //   ^ = {unknown}
            //       ^^^^^^^^^^^^ error: type cycle detected: 'X->Y->X'
            type Y = X
            //   ^ = {unknown}
            //       ^ error: type cycle detected: 'Y->X->Y'
            "#)
    }

    @TestCase
    func anAliasThatLeadsIntoACycleIsOnOne() {
        // N92: `Z` is on `X`'s cycle as well, though `X`'s is named by `Y`
        checkSignatureTypes(#"
            package m
            type X = (Y, Z)
            //   ^ = {unknown}
            //       ^^^^^^ error: type cycle detected: 'X->Y->X'
            type Y = X
            //   ^ = {unknown}
            //       ^ error: type cycle detected: 'Y->X->Y'
            type Z = X
            //   ^ = {unknown}
            //       ^ error: type cycle detected: 'Z->X->Z'
            "#)
    }

    @TestCase
    func aCycleThroughTheArgumentsOfAGenericAlias() {
        // N92: a path's arguments are searched before it
        checkSignatureTypes(#"
            package m
            type A<T> = (T, AX)
            //   ^ <T> = {unknown}
            //          ^^^^^^^ error: type cycle detected: 'A->AX->A'
            type AX = A<AY>
            //   ^^ = {unknown}
            //        ^^^^^ error: type cycle detected: 'AX->AY->AX'
            type AY = AX
            //   ^^ = {unknown}
            //        ^^ error: type cycle detected: 'AY->AX->AY'
            "#)
    }

    @TestCase
    func anAliasOnACycleKeepsItsOtherErrors() {
        // N89, N92, N93
        checkSignatureTypes(#"
            package m
            type X = (Nope, X, Y)
            //   ^ = {unknown}
            //       ^^^^^^^^^^^^ error: type cycle detected: 'X->Y->X'
            //        ^^^^ error: undeclared type name 'Nope'
            //              ^ error: undeclared type name 'X'
            type Y = X
            //   ^ = {unknown}
            //       ^ error: type cycle detected: 'Y->X->Y'
            "#)
    }

    @TestCase
    func aNameThatIsNoType() {
        // N94: a constructor cjc counts as no name
        checkSignatureTypes(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public func h(): Unit {}
            //          ^ () -> Unit
            //- /main.cj module=m package=m
            package m
            import m.a
            func g(): Unit {}
            //   ^ () -> Unit
            let v = 1
            //  ^ _
            enum E { Red }
            //   ^ E
            //       ^^^ E
            func f(a: g, b: v, c: a, d: Red, e: a.h): Unit {}
            //   ^ ({unknown}, {unknown}, {unknown}, {unknown}, {unknown}) -> Unit
            //        ^ error: 'g' is not a type
            //              ^ error: 'v' is not a type
            //                    ^ error: 'a' is not a type
            //                          ^^^ error: undeclared type name 'Red'
            //                                  ^^^ error: 'h' is not a type
            "#)
    }

    @TestCase
    func aPathOfSegmentsNotResolved() {
        // N89, N94, N95: each segment not resolved, up to the end
        checkSignatureTypes(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class K {}
            //           ^ K <: Object
            //- /main.cj module=m package=m
            package m
            import m.a
            class C {}
            //    ^ C <: Object
            func g(): Unit {}
            //   ^ () -> Unit
            func f<T>(a: a.Nope, b: C.D, c: T.U, d: nopkg.C, e: g.X, k: a.Nope.Z, n: a.K.Q): Unit {}
            //   ^ <T>({unknown}, {unknown}, {unknown}, {unknown}, {unknown}, {unknown}, {unknown}) -> Unit
            //           ^^^^^^ error: undeclared type name 'Nope'
            //                      ^^^ error: undeclared type name 'D'
            //                              ^^^ error: undeclared type name 'U'
            //                                      ^^^^^^^ error: undeclared type name 'C'
            //                                      ^^^^^^^ error: undeclared type name 'nopkg'
            //                                                  ^^^ error: 'g' is not a type
            //                                                  ^^^ error: undeclared type name 'X'
            //                                                          ^^^^^^^^ error: undeclared type name 'Nope'
            //                                                          ^^^^^^^^ error: undeclared type name 'Z'
            //                                                                       ^^^^^ error: undeclared type name 'Q'
            "#)
    }

    @TestCase
    func aCFuncTakesOneTypeArgument() {
        // N96: cjc counts `CFunc`'s arguments before it asks for any
        checkSignatureTypes(#"
            package m
            foreign func h(a: CFunc, b: CFunc<Int64, Int64>): Unit
            //           ^ ({unknown}, {unknown}) -> Unit
            //                ^^^^^ error: type argument's number does not match type parameter's number
            //                          ^^^^^^^^^^^^^^^^^^^ error: type argument's number does not match type parameter's number
            "#)
    }

    @TestCase
    func anAliasDoesNotSeeItsOwnName() {
        // N93: cjc says no more of `X` than of `Nope`
        checkSignatureTypes(#"
            package m
            type X = Array<X>
            //   ^ = Array<{unknown}>
            //             ^ error: undeclared type name 'X'
            "#)
    }

    @TestCase
    func anUndeclaredType() {
        // N89
        checkSignatureTypes(#"
            package m
            func f(a: Nope): Unit {}
            //   ^ ({unknown}) -> Unit
            //        ^^^^ error: undeclared type name 'Nope'
            "#)
    }

    @TestCase
    func aGenericTypeOfNoArguments() {
        // N90
        checkSignatureTypes(#"
            package m
            class C<T> {}
            //    ^ C<T> <: Object
            interface I<T> {}
            //        ^ I<T>
            type A<T> = (T, T)
            //   ^ <T> = (T, T)
            func f(a: C, b: A): Unit {}
            //   ^ (C<{unknown}>, ({unknown}, {unknown})) -> Unit
            //        ^ error: generic type should be used with type argument
            //              ^ error: generic type should be used with type argument
            class X <: I {}
            //    ^ X <: Object & I<{unknown}>
            //         ^ error: generic type should be used with type argument
            extend C {}
            //     ^ C<{unknown}>
            //     ^ error: generic type should be used with type argument
            "#)
    }

    @TestCase
    func tooManyOrTooFewTypeArguments() {
        // N91
        checkSignatureTypes(#"
            package m
            class K {}
            //    ^ K <: Object
            class D<T, U> {}
            //    ^ D<T, U> <: Object
            func f<T>(a: D<Int64>, b: K<Int64>, c: T<Int64>): Unit {}
            //   ^ <T>(D<Int64, {unknown}>, K, T) -> Unit
            //           ^^^^^^^^ error: type argument's number does not match type parameter's number
            //                        ^^^^^^^^ error: type argument's number does not match type parameter's number
            //                                     ^^^^^^^^ error: type argument's number does not match type parameter's number
            "#)
    }

    @TestCase
    func thisIsTheReturnTypeOfAnInstanceFunctionOfAClass() {
        // N88
        checkSignatureTypes(#"
            package m
            open class C {
            //         ^ C <: Object
                func me(): This {
            //       ^^ () -> This
                    this
                }
            }
            "#)
    }

    @TestCase
    func thisAnywhereElseIsAnError() {
        // N88
        checkSignatureTypes(#"
            package m
            interface I {
            //        ^ I
                func me(): This
            //       ^^ () -> {unknown}
            //             ^^^^ error: 'This' type is not allowed
            }
            struct S {
            //     ^ S
                func me(): This {
            //       ^^ () -> {unknown}
            //             ^^^^ error: 'This' type is not allowed
                    this
                }
            }
            class C {
            //    ^ C <: Object
                func opt(): ?This {
            //       ^^^ () -> Option<{unknown}>
            //               ^^^^ error: 'This' type is not allowed
                    None
                }
                func take(c: This): Unit {}
            //       ^^^^ ({unknown}) -> Unit
            //               ^^^^ error: 'This' type is not allowed
                static func make(): This {
            //              ^^^^ () -> {unknown}
            //                      ^^^^ error: 'This' type is not allowed here
                    C()
                }
            }
            "#)
    }

    @TestCase
    func typesOfTheCompilersOwn() {
        checkSignatureTypes(#"
            package m
            func f(a: VArray<Int64, $2>, b: CPointer<Int8>, c: CString, d: CFunc<(Int64) -> Unit>): Unit {}
            //   ^ (VArray<Int64, $2>, CPointer<Int8>, CString, CFunc<(Int64) -> Unit>) -> Unit
            "#)
    }

    @TestCase
    func aFunctionsTypeParameterIsItsOwnNotItsTypes() {
        // N55
        // arrange
        let (db, _, c) = declOf(#"
            package m
            class C<T> {
                func f<T>(x: T): T {
                    x
                }
                func g(x: T): T {
                    x
                }
            }
            "#, "C")
        let member = {name: String => DefId(db, c.file(db), named(itemOf(db, c).getOrThrow().members, name).id)}
        let (f, g) = (member("f"), member("g"))
        // act
        let ofF = signatureTypes(db, f).params[0].kind(db)
        let ofG = signatureTypes(db, g).params[0].kind(db)
        // assert
        @Expect(ofF == ParamTy(f, 0), true)
        @Expect(ofG == ParamTy(c, 0), true)
    }

    @TestCase
    func equalTypesAreOneId() {
        // arrange
        let (db, _, f) = declOf(#"
            package m
            class C<T> {}
            func f(a: C<Int64>, b: C<Int64>, c: C<Bool>): Unit {}
            "#, "f")
        // act
        let params = signatureTypes(db, f).params
        // assert
        @Expect(params[0], params[1])
        @Expect(params[0] != params[2], true)
    }

    @TestCase
    func anEditOfABodyLeavesTheSignatureTypesAndWhatReadThemAlone() {
        // arrange
        let (db, source, f) = declOf(#"
            package m
            func f(a: Int64): Int64 {
                a
            }
            "#, "f")
        paramTyCount(db, f)
        let before = signatureTypesReaderRuns.load()
        // act
        source.setText(db).to(Rope("package m\n\n// moved\nfunc f(a: Int64): Int64 {\n    a + 1\n}\n"))
        paramTyCount(db, f)
        // assert
        @Expect(signatureTypesReaderRuns.load(), before)
    }

    @TestCase
    func anEditOfATypeRunsAgainWhatReadTheSignatureTypes() {
        // arrange
        let (db, source, f) = declOf(#"
            package m
            func f(a: Int64): Int64 {
                a
            }
            "#, "f")
        paramTyCount(db, f)
        let before = signatureTypesReaderRuns.load()
        // act
        source.setText(db).to(Rope("package m\nfunc f(a: Int64, b: Bool): Int64 {\n    a\n}\n"))
        // assert
        @Expect(paramTyCount(db, f), 2)
        @Expect(signatureTypesReaderRuns.load(), before + 1)
    }
}


/**
 * The declarations of std's `.cjo`s as types: what cjc resolved, read back.
 */
@Test
class BinarySignatureTypesTest {
    @TestCase
    func anEnumOfStdCoreAndAMemberOfItsParameter() {
        // arrange
        let (db, core) = stdPackage("std.core")
        let option = exportOf(db, core, "Option")
        let getOrThrow = DefId(db, option.file(db), itemOf(db, option).getOrThrow().members.iterator().filter {
            member => member.names == ["getOrThrow"]
        }.next().getOrThrow().id)
        // act
        let ofOption = signatureTypes(db, option)
        let ofGetOrThrow = signatureTypes(db, getOrThrow)
        // assert
        @Expect(ofOption.text(db, ItemKind.Enum), "Option<T>")
        @Expect(ofGetOrThrow.ty.map {ty => ty.kind(db) == ParamTy(option, 0)}, Some(true))
    }

    @TestCase
    func aGenericFunctionOfAGenericStruct() {
        // arrange
        let (db, core) = stdPackage("std.core")
        let array = exportOf(db, core, "Array")
        let map = DefId(db, array.file(db), named(itemOf(db, array).getOrThrow().members, "map").id)
        // act
        let text = signatureTypes(db, map).text(db, ItemKind.Func)
        // assert
        @Expect(text, "<R>((T) -> R) -> Array<R>")
    }

    @TestCase
    func overloadsOfAFunctionAndABound() {
        // arrange
        let (db, core) = stdPackage("std.core")
        // act
        let texts = (packageExports(db, core).names.get("println") ?? []).map {
            def => signatureTypes(db, def.id).text(db, ItemKind.Func)
        }
        // assert
        @Expect(texts.contains("(String) -> Unit"), true)
        @Expect(texts.contains("<T>(T) -> Unit where T <: ToString"), true)
    }

    @TestCase
    func anAliasAndTypesOfTheCompilersOwn() {
        // arrange
        let (db, core) = stdPackage("std.core")
        // act
        let byte = signatureTypes(db, exportOf(db, core, "Byte")).text(db, ItemKind.TypeAlias)
        let pointer = signatureTypes(db, exportOf(db, core, "CPointer")).text(db, ItemKind.BuiltIn)
        let rawArray = signatureTypes(db, exportOf(db, core, "RawArray")).text(db, ItemKind.BuiltIn)
        // assert
        @Expect(byte, "= UInt8")
        @Expect(pointer, "CPointer<T> where T <: CType")
        @Expect(rawArray, "RawArray<T>")
    }

    @TestCase
    func anAliasCjcKeptInAType() {
        // arrange: `String.toArray(): Array<Byte>`, `Byte` an alias in the `.cjo`'s types
        let (db, core) = stdPackage("std.core")
        let string = exportOf(db, core, "String")
        let toArray = DefId(db, string.file(db), named(itemOf(db, string).getOrThrow().members, "toArray").id)
        // act
        let text = signatureTypes(db, toArray).text(db, ItemKind.Func)
        // assert
        @Expect(text, "() -> Array<UInt8>")
    }

    @TestCase
    func aClassOfNoSuperclassIsAnObjectAsASourcesIs() {
        // arrange
        let (db, core) = stdPackage("std.core")
        // act
        let text = signatureTypes(db, exportOf(db, core, "Exception")).text(db, ItemKind.Class)
        // assert
        @Expect(text, "Exception <: Object & ToString")
    }

    @TestCase
    func anExtendHasTheBoundsItWritesNotThoseOfItsType() {
        // arrange: `extend<K, V> HashMap<K, V> <: Equatable<…> where V <: Equatable<V>`; cjc adds
        // `K`'s bounds of `HashMap` to the `.cjo`'s
        let (db, collection) = stdPackage("std.collection", others: ["std.core"])
        let hashMap = exportOf(db, collection, "HashMap")
        // act
        let texts = (packageExtends(db, collection).get(ExtendedType.DeclType(hashMap)) ?? []).map {
            def => signatureTypes(db, def).text(db, ItemKind.Extend)
        }
        // assert
        @Expect(texts.contains("<K, V> HashMap<K, V> <: Equatable<HashMap<K, V>> where V <: Equatable<V>"), true)
    }

    @TestCase
    func aTypeOfAPackageItImports() {
        // arrange: `ArrayList.toArray` of std.collection, its `Array` std.core's
        let (db, collection) = stdPackage("std.collection", others: ["std.core"])
        let list = exportOf(db, collection, "ArrayList")
        let toArray = DefId(db, list.file(db), named(itemOf(db, list).getOrThrow().members, "toArray").id)
        // act
        let text = signatureTypes(db, toArray).text(db, ItemKind.Func)
        // assert
        @Expect(text, "() -> Array<T>")
    }
}

/**
 * A database of the packages `name` and `others` of std, and the first.
 */
func stdPackage(name: String, others!: Array<String> = []): (AnalysisDatabase, PackageRef) {
    let reads: Array<CjoFileRead> = [name].concat(others).map {one => stdCjoRead(one, stdCjo(one))}
    let parsed = Fixture.parse("package m\n")
    let db = parsed.database(binaries: reads)
    let source = db.sourceFile(parsed.files[0].fileId).getOrThrow()
    let pkg = packageOfFile(db, source).getOrThrow()
    (db, packageIndex(db).find(name, from: PackageRef.Source(pkg)).getOrThrow())
}

/**
 * The declaration `name` `pkg` exports, the first if it has more.
 */
func exportOf(db: AnalysisDatabase, pkg: PackageRef, name: String): DefId {
    (packageExports(db, pkg).names.get(name) ?? throw IllegalStateException("no ${name}"))[0].id
}
