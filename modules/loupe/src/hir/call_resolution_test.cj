package loupe.hir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.AnalysisDatabase
import loupe.fixture.*

private func callResolutionFixture(source: String): (AnalysisDatabase, DefId, Body) {
    let fixture = Fixture.parse(source)
    let db = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
    let file = db.sourceFile(fixture.files[0].fileId).getOrThrow()
    let item = itemTree(db, file).items.filter { item => item.names.contains("test") }[0]
    let def = DefId(db, ItemFile.Source(file), item.id)
    (db, def, body(db, def))
}

private func callsNamed(hir: Body, inferred: InferenceResult, name: String): Array<CallResolution> {
    let found = ArrayList<CallResolution>()
    for (i in 0..hir.exprs.size) {
        match (hir.exprs[i]) {
            case PathExpr(one, _) where one == name =>
                if (let Some(call) <- inferred.callOf(ExprId(i))) {
                    found.add(call)
                }
            case FieldExpr(_, one, _) where one == name =>
                if (let Some(call) <- inferred.callOf(ExprId(i))) {
                    found.add(call)
                }
            case _ => ()
        }
    }
    found.toArray()
}

@Test
class CallResolutionTest {
    @TestCase
    func explicitAndInferredSubstitutionsBelongToTheirDeclaration() {
        // arrange
        let (db, def, hir) = callResolutionFixture(
            #"
            package m
            func identity<T>(x: T): T { x }
            func test(): Unit { identity(1); identity<Bool>(true) }
            "#
        )

        // act
        let inferred = inferBody(db, def)

        // assert
        let calls = callsNamed(hir, inferred, "identity")
        @Expect(calls.size, 2)
        @Expect(calls.map { one => one.outcome }, [CallResolutionOutcome.Resolved, CallResolutionOutcome.Resolved])
        @Expect(calls.map { one => one.bindings[0].ty.text(db) }, ["Int64", "Bool"])
        for (one in calls) {
            @Expect(one.bindings[0].owner, GenericOwner.Declaration(one.decl.getOrThrow()))
            @Expect(one.bindings[0].index, 0)
        }
    }

    @TestCase
    func memberBindingsRetainReceiverAndFunctionOwners() {
        // arrange
        let (db, def, hir) = callResolutionFixture(
            #"
            package m
            class Box<T> {
                public init() {}
                public func pair<U>(x: T, y: U): U { y }
            }
            func test(): Unit { Box<Int64>().pair(1, true) }
            "#
        )

        // act
        let inferred = inferBody(db, def)

        // assert
        let call = callsNamed(hir, inferred, "pair")[0]
        @Expect(call.outcome, CallResolutionOutcome.Resolved)
        @Expect(call.bindings.map { one => one.ty.text(db) }, ["Bool", "Int64"])
        let decl = call.decl.getOrThrow()
        @Expect(call.bindings[0].owner, GenericOwner.Declaration(decl))
        @Expect(call.bindings[1].owner, GenericOwner.Declaration(parentOf(db, decl).getOrThrow()))
    }

    @TestCase
    func constructorsKeepTheirTypeBindingsSeparatelyFromInitializerIdentity() {
        // arrange
        let (db, def, hir) = callResolutionFixture(
            #"
            package m
            class Box<T> { public init(x: T) {} }
            func test(): Unit { Box(1) }
            "#
        )

        // act
        let inferred = inferBody(db, def)

        // assert
        let call = callsNamed(hir, inferred, "Box")[0]
        @Expect(call.outcome, CallResolutionOutcome.Resolved)
        @Expect(call.decl, inferred.initializerOf(call.expr))
        @Expect(call.bindings[0].ty.text(db), "Int64")
        @Expect(call.bindings[0].owner, GenericOwner.Declaration(parentOf(db, call.decl.getOrThrow()).getOrThrow()))
    }

    @TestCase[explicit in [false, true]]
    func chainedApplicationsRetainTheSharedFinalSolution(explicit: Bool) {
        // arrange
        let application = if (explicit) { "factory<Int64>()" } else { "factory()" }
        let (db, def, hir) = callResolutionFixture(
            """
            package m
            func factory<T>(): (T) -> (T) -> T { {x => {y => y}} }
            func test(): Unit { ${application}(1)(2) }
            """
        )

        // act
        let inferred = inferBody(db, def)

        // assert
        @Expect(inferred.calls.size, 3)
        let first = callsNamed(hir, inferred, "factory")[0]
        for (call in inferred.calls) {
            @Expect(call.outcome, CallResolutionOutcome.Resolved)
            @Expect(call.bindings[0].ty.text(db), "Int64")
            @Expect(call.bindings[0].owner, first.bindings[0].owner)
            @Expect(!hasInferVars(db, call.signature.getOrThrow()))
        }
    }

    @TestCase
    func selectedCandidateDoesNotKeepSpeculativeBindings() {
        // arrange
        let (db, def, hir) = callResolutionFixture(
            #"
            package m
            func select<T>(seed: String): ((Bool) -> String) -> T where T <: ToString {
                {f => throw Exception()}
            }
            func select<T>(seed: T): ((T) -> String) -> T where T <: ToString { {f => seed} }
            func test(): Unit { select(1)({x => x.toString()}) }
            "#
        )

        // act
        let inferred = inferBody(db, def)

        // assert
        let call = callsNamed(hir, inferred, "select")[0]
        @Expect(call.outcome, CallResolutionOutcome.Resolved)
        @Expect(call.bindings.size, 1)
        @Expect(call.bindings[0].ty.text(db), "Int64")
        @Expect(call.bindings[0].owner, GenericOwner.Declaration(call.decl.getOrThrow()))
        @Expect(inferred.diagnostics.isEmpty())
    }

    @TestCase
    func localFunctionsAndValuesSucceedWithoutDeclarationTargets() {
        // arrange
        let (db, def, hir) = callResolutionFixture(
            #"
            package m
            func test(): Unit {
                func local<T>(x: T): T { x }
                local(true)
                let value: (Int64) -> Int64 = {x => x}
                value(1)
            }
            "#
        )

        // act
        let inferred = inferBody(db, def)

        // assert
        let local = callsNamed(hir, inferred, "local")[0]
        @Expect(local.outcome, CallResolutionOutcome.Resolved)
        @Expect(local.decl.isNone())
        @Expect(local.local.isSome())
        let value = callsNamed(hir, inferred, "value")[0]
        @Expect(value.outcome, CallResolutionOutcome.Resolved)
        @Expect(value.decl.isNone())
        @Expect(value.local.isNone())
    }

    @TestCase
    func localBindingsKeepCapturedOuterAndShadowedBinderIdentities() {
        // arrange
        let (db, def, hir) = callResolutionFixture(
            #"
            package m
            func test<A>(x: A): Unit {
                func outer<T>(y: T): Unit {
                    func inner<T>(z: T): (A, T) { (x, z) }
                    inner(true)
                }
                outer(1)
            }
            "#
        )

        // act
        let inferred = inferBody(db, def)

        // assert
        let call = callsNamed(hir, inferred, "inner")[0]
        @Expect(call.outcome, CallResolutionOutcome.Resolved)
        @Expect(call.bindings[0].ty.text(db), "Bool")
        @Expect(call.bindings[1].owner, GenericOwner.Declaration(def))
        @Expect(call.bindings[1].ty.text(db), "A")
        @Expect(call.bindings[0].owner != callsNamed(hir, inferred, "outer")[0].bindings[0].owner)
    }

    @TestCase
    func ambiguityAndMissingCallsAreExplicit() {
        // arrange
        let (db, def, hir) = callResolutionFixture(
            #"
            package m
            func pick(x: Int8): Int8 { x }
            func pick(x: Int16): Int16 { x }
            func test(): Unit { pick(1); missing() }
            "#
        )

        // act
        let inferred = inferBody(db, def)

        // assert
        @Expect(callsNamed(hir, inferred, "pick")[0].outcome, CallResolutionOutcome.Ambiguous)
        @Expect(callsNamed(hir, inferred, "missing")[0].outcome, CallResolutionOutcome.Unresolved)
        @Expect(callsNamed(hir, inferred, "pick")[0].bindings.isEmpty())
    }
    @TestCase
    func failedGenericCallsDoNotExposeCandidateSubstitutions() {
        // arrange
        let (db, def, hir) = callResolutionFixture(
            #"
            package m
            func take<T>(x: T, y: String): T { x }
            func test(): Unit { take(1, true); take<Bool>(1, "s") }
            "#
        )

        // act
        let inferred = inferBody(db, def)

        // assert
        let calls = callsNamed(hir, inferred, "take")
        @Expect(calls.size, 2)
        for (call in calls) {
            @Expect(call.outcome, CallResolutionOutcome.Unresolved)
            @Expect(call.bindings.isEmpty())
        }
    }
    @TestCase
    func initializerDelegationKeepsTheReceiverGenericBindings() {
        // arrange
        let fixture = Fixture.parse(
            #"
            package m
            open class Base<T> { public init(x: T) {} }
            class Derived<T> <: Base<T> {
                public init(x: T) { super(x) }
                public init(x: T, extra: Bool) { this(x) }
            }
            "#
        )
        let db = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let file = db.sourceFile(fixture.files[0].fileId).getOrThrow()
        let item = itemTree(db, file).items.filter { item => item.names.contains("Derived") }[0]
        let derived = DefId(db, ItemFile.Source(file), item.id)
        let constructors = item.members.filter { member => member.kind == ItemKind.Init }

        // act
        let results =
            constructors
                .map { member => inferBody(db, DefId(db, ItemFile.Source(file), member.id)) }

        // assert
        @Expect(results.size, 2)
        for (result in results) {
            @Expect(result.calls.size, 1)
            let call = result.calls[0]
            @Expect(call.outcome, CallResolutionOutcome.Resolved)
            @Expect(call.bindings.size, 1)
            @Expect(call.bindings[0].owner,
                GenericOwner.Declaration(parentOf(db, call.decl.getOrThrow()).getOrThrow()))
            @Expect(call.bindings[0].ty.kind(db), ParamTy(GenericOwner.Declaration(derived), 0))
            @Expect(result.diagnostics.isEmpty())
        }
    }
}
