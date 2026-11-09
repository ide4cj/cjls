package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*

@Test
class LambdaMemberChoicesTest {
    @TestCase[imported in ["import dep", "import dep as named"]]
    func namespaceImportsDoNotSupplyReceiverCandidates(imported: String): Unit {
        // arrange
        let fixture =
            """
            //- /main.cj module=m package=m deps=dep
            package m
            ${imported}
            func test(): Unit { let target = {x => x.lambdaImported} }
            //- /dep/lib.cj module=dep package=dep
            package dep
            public class Provider { public let lambdaImported: Int64 = 1 }
            """

        // act
        let choices = memberChoiceNames(fixture)

        // assert
        @Expect(choices, [Array<String>()])
    }

    @TestCase[imported in ["import dep.Provider", "import dep.Provider as Named", "import dep.*"]]
    func explicitAndGlobImportsSupplyReceiverCandidates(imported: String): Unit {
        // arrange
        let fixture =
            """
            //- /main.cj module=m package=m deps=dep
            package m
            ${imported}
            func test(): Unit { let target = {x => x.lambdaImported} }
            //- /dep/lib.cj module=dep package=dep
            package dep
            public class Provider { public let lambdaImported: Int64 = 1 }
            """

        // act
        let choices = memberChoiceNames(fixture)

        // assert
        @Expect(choices, [["Provider"]])
    }

    @TestCase
    func importsAcrossPackageFilesAndReexportsSupplyCandidates(): Unit {
        // arrange
        let fixture =
            #"
            //- /main.cj module=m package=m deps=bridge
            package m
            func test(): Unit { let target = {x => x.lambdaImported} }
            //- /other.cj module=m package=m deps=bridge
            package m
            import bridge.*
            //- /bridge/lib.cj module=bridge package=bridge deps=dep
            package bridge
            public import dep.Provider as Exported
            //- /dep/lib.cj module=dep package=dep
            package dep
            public class Provider { public let lambdaImported: Int64 = 1 }
            "#

        // act
        let choices = memberChoiceNames(fixture)

        // assert
        @Expect(choices, [["Provider"]])
    }

    @TestCase
    func bareInheritedMembersPreferTheGeneralOwner(): Unit {
        // arrange
        let fixture =
            #"
            package m
            open class Base { public let lambdaInherited: Int64 = 1 }
            class Derived <: Base {}
            func test(): Unit { let target = {x => x.lambdaInherited} }
            "#

        // act
        let choices = memberChoiceNames(fixture)

        // assert
        @Expect(choices, [["Base"]])
    }

    @TestCase
    func resultConstraintsKeepSubtypeAlternativesForBodyTrials(): Unit {
        // arrange
        let fixture =
            #"
            package m
            open class Base { public let lambdaInherited: Int64 = 1 }
            class Derived <: Base {}
            func test(): Unit { let target = {x => x.lambdaInherited + 1} }
            "#

        // act
        let choices = memberChoiceNames(fixture)

        // assert
        @Expect(choices, [["Base", "Derived"]])
    }

    @TestCase
    func nestedShadowingDoesNotConstrainAnOuterParameter(): Unit {
        // arrange
        let fixture =
            #"
            package m
            class Provider { public let lambdaNested: Int64 = 1 }
            func test(): Unit { let target = {x => {x: Provider => x.lambdaNested}} }
            "#

        // act
        let choices = memberChoiceNames(fixture)

        // assert
        @Expect(choices, [Array<String>()])
    }

    @TestCase
    func nestedCapturesCanConstrainTheOuterParameter(): Unit {
        // arrange
        let fixture =
            #"
            package m
            class Provider { public let lambdaNested: Int64 = 1 }
            func test(): Unit { let target = {x => {=> x.lambdaNested}} }
            "#

        // act
        let choices = memberChoiceNames(fixture)

        // assert
        @Expect(choices, [["Provider"]])
    }
    @TestCase
    func testOnlyExtensionsDoNotReintroduceProductionCandidates(): Unit {
        // arrange
        let fixture =
            #"
            //- /main.cj module=m package=m
            package m
            func test(): Unit { let target = {x => x.lambdaFromTest} }
            //- /provider_test.cj module=m package=m
            package m
            class Provider { public let lambdaFromTest: Int64 = 1 }
            extend Provider {}
            "#

        // act
        let choices = memberChoiceNames(fixture)

        // assert
        @Expect(choices, [Array<String>()])
    }

    @TestCase
    func testFilesCanUseTheirTestOnlyReceiverCandidates(): Unit {
        // arrange
        let fixture =
            #"
            //- /main_test.cj module=m package=m
            package m
            func test(): Unit { let target = {x => x.lambdaFromTest} }
            //- /provider_test.cj module=m package=m
            package m
            class Provider { public let lambdaFromTest: Int64 = 1 }
            extend Provider {}
            "#

        // act
        let choices = memberChoiceNames(fixture)

        // assert
        @Expect(choices, [["Provider"]])
    }

    @TestCase[
        file in ["main.cj", "main_test.cj"],
        imported in ["import dep.Provider", "import dep.*"]
    ]
    func dependencyTestsNeverSupplyImportedReceiverCandidates(
        file: String,
        imported: String
    ): Unit {
        // arrange
        let fixture =
            """
            //- /${file} module=m package=m deps=dep
            package m
            ${imported}
            func test(): Unit { let target = {x => x.lambdaFromDependencyTest} }
            //- /dep/provider_test.cj module=dep package=dep
            package dep
            public class Provider { public let lambdaFromDependencyTest: Int64 = 1 }
            """

        // act
        let choices = memberChoiceNames(fixture)

        // assert
        @Expect(choices, [Array<String>()])
    }
    @TestCase
    func inheritedGenericCoverageIsSubstitutedToTheReceiverOwner(): Unit {
        // arrange
        let fixture =
            #"
            package m
            open class Base<T> {
                public prop inherited: T { get() { throw Exception("unused") } }
            }
            class Derived<U, V> <: Base<U> {
                public prop own: V { get() { throw Exception("unused") } }
            }
            class Other {
                public let inherited: Int64 = 1
                public let own: Int64 = 1
            }
            func test(): Unit { let target = {x => x.inherited + 1 + x.own} }
            "#

        // act
        let choices = memberChoiceNames(fixture)

        // assert: Other prevents the all-pruned fallback from hiding lost Derived<U, V> coverage.
        @Expect(choices, [["Derived", "Other"]])
    }
}

/**
 * Candidate names for the first binding's lambda, without invoking body inference.
 */
private func memberChoiceNames(text: String): Array<Array<String>> {
    let fixture = Fixture.parse(text)
    let db = fixture.database()
    let source =
        db.sourceFile(fixture.files[0].fileId) ??
            throw IllegalStateException("fixture source is missing")
    let item = itemTree(db, source).items.filter { one => one.names.contains("test") }[0]
    let def = DefId(db, ItemFile.Source(source), item.id)
    let hir = body(db, def)
    let value = hir.value ?? throw IllegalStateException("test body is missing")
    let stmts =
        match (hir[value]) {
            case BlockExpr(stmts) => stmts
            case _ => throw IllegalStateException("test must have a block body")
        }
    let lambda =
        match (stmts[0]) {
            case LetStmt(_, _, Some(expr)) => expr
            case _ => throw IllegalStateException("first statement must bind a lambda")
        }
    let (params, block) =
        match (hir[lambda]) {
            case LambdaExpr(params, block) => (params, block)
            case _ => throw IllegalStateException("binding must contain a lambda")
        }
    lambdaMemberChoices(db, def, params, block)
        .map {
            choices =>
            choices
                .map {
                    owner =>
                    match (owner) {
                        case DeclType(id) =>
                            itemOf(db, id).flatMap { one => one.names.get(0) } ?? "<missing>"
                        case PrimType(name) => name
                        case BuiltInHead(kind) => kind.toString()
                    }
                }
        }
}
