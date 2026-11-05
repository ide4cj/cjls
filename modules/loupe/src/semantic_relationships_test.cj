package loupe

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import calca.CancelledException
import ginkgo.TextRange
import rope.Rope
import loupe.db.{MappedSpan, SpanOrigin}
import loupe.fixture.*
import loupe.hir.*

@Test
class SemanticRelationshipsTest {
    @TestCase
    func composeIdentityThroughUsageOwnerAndCalls(): Unit {
        // arrange
        let fixture = Fixture.parse("func tar$0get() {}\nfunc caller() { target(); target() }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)
        let target = analysis.at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]

        // act
        let uses = target.usages().getOrThrow().entries
        let calls =
            uses
                .filter { use => !use.isDeclaration }
                .map {
                    use =>
                    match (use.owner) {
                        case ObjectOwner(owner) => owner.outgoingCalls()
                        case _ => throw FixtureException("call has no owner")
                    }
                }
        let incoming = target.incomingCalls()

        // assert
        @Expect(uses.size, 3)
        @Expect(calls.size, 2)
        @Expect(calls.all { outgoing => outgoing.edges.size == 2 })
        @Expect(calls.all { outgoing => outgoing.edges.all { edge => edge.callee.identity == target.identity } })
        @Expect(incoming.size, 2)
        @Expect(incoming[0].site.focusRange != incoming[1].site.focusRange)
        @Expect(incoming.all { edge => semanticOriginText(edge.caller) == ["caller"] })
    }

    @TestCase
    func shadowedLocalsHaveSeparateUsageSets(): Unit {
        // arrange
        let fixture = Fixture.parse("func f() { let x = 1; x; { let x = 2; x$0 } }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let target =
            SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]

        // act
        let uses = target.usages().getOrThrow().entries

        // assert
        @Expect(uses.size, 2)
        @Expect(uses.filter { use => use.isDeclaration }.size, 1)
        @Expect(uses.all { use => use.target.identity == target.identity })
    }

    @TestCase
    func nestedFunctionsAndLambdasHaveTheirOwnCallOwners(): Unit {
        // arrange
        let fixture = Fixture.parse(
            "func tar$0get() {}\nfunc outer() { func nested() { target() }; let lambda = { => target() } }"
        )
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)
        let target = analysis.at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]
        let outerOffset = fixture.files[0].text.indexOf("outer").getOrThrow()
        let outer = analysis.at(at.fileId, outerOffset).getOrThrow().definitions.getOrThrow()[0]

        // act
        let uses = target.usages().getOrThrow().entries.filter { use => !use.isDeclaration }
        let nestedCalls =
            uses
                .map {
                    use =>
                    match (use.owner) {
                        case ObjectOwner(owner) => owner.outgoingCalls()
                        case _ => throw FixtureException("nested call has no owner")
                    }
                }
        let outerCalls = outer.outgoingCalls()

        // assert
        @Expect(uses.size, 2)
        @Expect(outerCalls.edges.size, 0)
        @Expect(nestedCalls.all { result => result.edges.size == 1 })
        @Expect(uses.any { use => match (use.owner) {
            case ObjectOwner(owner) => match (owner.identity) { case LocalIdentity(_, _) => true; case _ => false }
            case _ => false
        } })
        @Expect(uses.any { use => match (use.owner) {
            case ObjectOwner(owner) => match (owner.identity) { case ExpressionIdentity(_, _) => true; case _ => false }
            case _ => false
        } })
    }

    @TestCase
    func emptyAndUnavailableBodiesAndFunctionalValuesStayDistinct(): Unit {
        // arrange
        let fixture = Fixture.parse(
            "func emp$0ty() {}\ninterface I { func abstracted(): Unit }\nfunc invoke(callback: () -> Unit) { callback() }"
        )
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)
        let empty = analysis.at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]
        let unavailable =
            analysis
                .at(at.fileId, fixture.files[0].text.indexOf("abstracted").getOrThrow())
                .getOrThrow()
                .definitions
                .getOrThrow()[0]
        let invoke =
            analysis
                .at(at.fileId, fixture.files[0].text.indexOf("invoke").getOrThrow())
                .getOrThrow()
                .definitions
                .getOrThrow()[0]

        // act
        let emptyCalls = empty.outgoingCalls()
        let unavailableCalls = unavailable.outgoingCalls()
        let invocation = invoke.outgoingCalls()

        // assert
        @Expect(emptyCalls.edges.isEmpty())
        @Expect(emptyCalls.gaps.isEmpty())
        @Expect(unavailableCalls.gaps.any { gap => gap.reason == "unavailable-body" })
        @Expect(invocation.edges.isEmpty())
        @Expect(invocation.gaps.any { gap => gap.reason == "functional-value" })
    }

    @TestCase
    func retainedRelationshipsCancelAfterWrites(): Unit {
        // arrange
        let fixture = Fixture.parse("func tar$0get() {}")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let object =
            SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]

        // act
        db.setFileText(at.fileId, Rope("func target() { 1 }"))

        // assert
        @AssertThrows[CancelledException](object.usages())
        @AssertThrows[CancelledException](object.outgoingCalls())
        @AssertThrows[CancelledException](object.incomingCalls())
        @AssertThrows[CancelledException](object.directSupertypes())
        @AssertThrows[CancelledException](object.directSubtypes())
        @AssertThrows[CancelledException](object.directImplementations())
    }

    @TestCase
    func aliasesOverloadsAndFileOwnersPreserveIdentity(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /a.cj module=m package=m.a
            package m.a
            public func tar$0get(x: Int64): Unit {}
            public func target(x: Bool): Unit {}
            //- /b.cj module=m package=m.b
            package m.b
            import m.a.target as alias
            func caller() { alias(1); alias(true) }
            "#
        )
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)
        let target = analysis.at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]

        // act
        let uses = target.usages().getOrThrow().entries
        let incoming = target.incomingCalls()

        // assert
        @Expect(uses.any { use => use.location.excerpt() == Some("alias") })
        @Expect(uses.any { use => match (use.owner) { case FileOwner(_) => true; case _ => false } })
        @Expect(incoming.size, 1)
        @Expect(incoming[0].callee.identity, target.identity)
        @Expect(incoming[0].site.excerpt(), Some("alias"))
    }

    @TestCase
    func binaryCallsComposeWithoutAttachedSource(): Unit {
        // arrange
        let fixture = Fixture.parse("package m\nfunc cal$0ler() { println(readln()) }")
        let db = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let at = fixture.cursor.getOrThrow()
        let caller =
            SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]

        // act
        let outgoing = caller.outgoingCalls()
        let calleeCalls = outgoing.edges.map { edge => edge.callee.outgoingCalls() }
        let incoming = outgoing.edges.map { edge => edge.callee.incomingCalls() }

        // assert
        @Expect(outgoing.edges.size, 2)
        @Expect(calleeCalls.all { calls => calls.edges.isEmpty() && calls.gaps.any { gap => gap.reason == "unavailable-body" } })
        @Expect(incoming.all { edges => edges.size == 1 && edges[0].caller.identity == caller.identity })
        @Expect(outgoing.edges.all { edge => match (edge.callee.identity) {
            case NamedIdentity(DeclDef(id)) => match (id.file(db)) { case Binary(_, _) => true; case _ => false }
            case _ => false
        } })
    }

    @TestCase
    func diamondAndExtendKeepImmediateEdgesAndProvenance(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /a.cj module=m package=m
            package m
            interface Root { func run(): Unit }
            interface Left <: Root {}
            interface Right <: Root {}
            interface Diamond <: Left & Right {}
            class Concrete {}
            extend Concrete <: Diamond { public func run(): Unit {} }
            "#
        )
        let db = fixture.database()
        let file = fixture.files[0]
        let analysis = SemanticAnalysis(db)
        let root =
            analysis
                .at(file.fileId, file.text.indexOf("Root {").getOrThrow())
                .getOrThrow()
                .definitions
                .getOrThrow()[0]
        let diamond =
            analysis
                .at(file.fileId, file.text.indexOf("Diamond <:").getOrThrow())
                .getOrThrow()
                .definitions
                .getOrThrow()[0]
        let implementation =
            analysis
                .at(file.fileId, file.text.indexOf("run(): Unit {}").getOrThrow())
                .getOrThrow()
                .definitions
                .getOrThrow()[0]

        // act
        let belowRoot = root.directSubtypes()
        let aboveDiamond = diamond.directSupertypes()
        let belowDiamond = diamond.directSubtypes()
        let members = implementation.directImplementations()

        // assert
        @Expect(belowRoot.size, 2)
        @Expect(aboveDiamond.size, 2)
        @Expect(aboveDiamond.all { edge => edge.subtype.identity == diamond.identity && edge.owner.identity == diamond.identity && edge.extension.isNone() })
        @Expect(belowDiamond.size, 1)
        @Expect(semanticOriginText(belowDiamond[0].subtype), ["Concrete"])
        @Expect(belowDiamond[0].extension.isSome())
        @Expect(belowDiamond[0].subtype.directSupertypes().any { edge => edge.supertype.identity == diamond.identity && edge.extension.isSome() })
        @Expect(belowDiamond[0].owner.identity, belowDiamond[0].extension.getOrThrow().identity)
        @Expect(members.size, 1)
        @Expect(semanticOriginText(members[0].declaration), ["run"])
        @Expect(members[0].extension.isSome())
        @Expect(members[0].owner.identity, belowDiamond[0].owner.identity)
    }

    @TestCase
    func nearestMemberEdgesExcludeTransitiveOverrides(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /a.cj module=m package=m
            package m
            open class Base { public open func run(): Unit {} }
            open class Mid <: Base { public open func run(): Unit {} }
            class Sub <: Mid { public override func r$0un(): Unit {} }
            "#
        )
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)
        let sub = analysis.at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]

        // act
        let direct = sub.directImplementations()
        let reverse = direct[0].declaration.directImplementers()
        let transitive: Array<DefId> =
            match (sub.identity) {
                case NamedIdentity(DeclDef(id)) => overriddenMembers(db, id);
                case _ => []
            }

        // assert
        @Expect(direct.size, 1)
        @Expect(transitive.size, 2)
        @Expect(semanticOriginText(direct[0].owner), ["Sub"])
        @Expect(reverse.size, 1)
        @Expect(reverse[0].implementation.identity, sub.identity)
    }

    @TestCase
    func localDefaultsAreGapsAndDoNotBecomeUnconditionalCalls(): Unit {
        // arrange
        let fixture = Fixture.parse(
            "func target(): Int64 { 1 }\nfunc outer() { func local(x: Int64 = target()): Unit {}; loc$0al() }"
        )
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let local =
            SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]

        // act
        let calls = local.outgoingCalls()

        // assert
        @Expect(calls.edges.isEmpty())
        @Expect(calls.gaps.any { gap => gap.reason == "default-arguments" })
    }

    @TestCase
    func unresolvedCallsAndVirtualCandidatesRetainCoverage(): Unit {
        // arrange
        let fixture = Fixture.parse(
            "interface I { func run(): Unit }\nfunc cal$0ler(i: I) { i.run(); missing() }"
        )
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let caller =
            SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]

        // act
        let calls = caller.outgoingCalls()

        // assert
        @Expect(calls.edges.size, 1)
        @Expect(calls.edges[0].isConservative)
        @Expect(calls.edges[0].resolution, "candidate")
        @Expect(calls.gaps.any { gap => gap.reason == "virtual-dispatch" })
        @Expect(calls.gaps.any { gap => gap.reason == "unresolved-call" })
    }

    @TestCase
    func fileLevelOccurrencesAndPartialUsageCoverageAreExplicit(): Unit {
        // arrange
        let fixture = Fixture.parse("func tar$0get(): Int64 { 1 }\nlet value = target()")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let target =
            SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]

        // act
        let result = target.usages().getOrThrow()
        let usage = result.entries.filter { entry => !entry.isDeclaration }[0]

        // assert
        @Expect(match (usage.owner) { case FileOwner(_) => true; case _ => false })
        @Expect(result.gaps, ["macro-origin-usages"])
    }

    @TestCase
    func expandedNestedBodyReportsUnavailableWithoutReinterpretingItsRanges(): Unit {
        // arrange
        let (db, file) = expansionDatabase(
            "package m\nimport m.ms.*\nfunc target() {}\nfunc f() { @A(1) }"
        )
        const OUTPUT = "let callback = { => target() }; callback"
        let call = answer(
            db,
            file,
            "A",
            OUTPUT,
            [MappedSpan(TextRange(0, OUTPUT.size), SpanOrigin.FromCall)]
        )
        let analysis = SemanticAnalysis(db)
        let selected = analysis
            .inFile(ItemFile.Expansion(call), OUTPUT.indexOf("{").getOrThrow())
            .getOrThrow()
        let lambda =
            selected
                .objects
                .filter {
                    object =>
                    match (object.identity) {
                        case ExpressionIdentity(_, _) => true
                        case _ => false
                    }
                }[0]

        // act
        let calls = lambda.outgoingCalls()

        // assert
        @Expect(calls.edges.isEmpty())
        @Expect(calls.gaps.size, 1)
        @Expect(calls.gaps[0].reason, "unavailable-body")
        @Expect(calls.gaps[0].site.isNone())
        @Expect(match (lambda.origins()[0]) { case SourceOrigin(location) => location.file == ItemFile.Expansion(call); case _ => false })
    }

    @TestCase
    func classMemberKeepsTheExtensionGrantingItsInterface(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /a.cj module=m package=m
            package m
            interface I { func run(): Unit }
            class Concrete { public func r$0un(): Unit {} }
            extend Concrete <: I {}
            "#
        )
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)
        let member = analysis.at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]

        // act
        let edges = member.directImplementations()
        let reverse = edges[0].declaration.directImplementers()

        // assert
        @Expect(edges.size, 1)
        @Expect(semanticOriginText(edges[0].owner), ["Concrete"])
        @Expect(edges[0].extension.isSome())
        @Expect(reverse.size, 1)
        @Expect(reverse[0].implementation.identity, member.identity)
        @Expect(reverse[0].extension.getOrThrow().identity, edges[0].extension.getOrThrow().identity)
    }

    @TestCase
    func mainAndFinalizerCallsRetainCallableOwners(): Unit {
        // arrange
        let fixture = Fixture.parse(
            "func tar$0get(): Unit {}\nmain() { target() }\nclass C { ~init() { target() } }"
        )
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let target =
            SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]

        // act
        let incoming = target.incomingCalls()
        let usages = target.usages().getOrThrow().entries.filter { use => !use.isDeclaration }

        // assert
        @Expect(incoming.size, 2)
        @Expect(usages.size, 2)
        @Expect(usages.all { use => match (use.owner) { case ObjectOwner(_) => true; case _ => false } })
        @Expect(incoming.all { edge => edge.caller.outgoingCalls().edges.size == 1 })
    }

    @TestCase
    func operatorsHaveIncomingEdgesWithoutIdentifierWordFiltering(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /decl.cj module=m package=m
            package m
            public class C { public operator func +(rhs: C): C { this } }
            //- /use.cj module=m package=m
            package m
            func caller(c: C): C { c + c }
            "#
        )
        let db = fixture.database()
        let analysis = SemanticAnalysis(db)
        let written = fixture.files[0]
        let target =
            analysis
                .at(written.fileId, written.text.indexOf("+").getOrThrow())
                .getOrThrow()
                .definitions
                .getOrThrow()[0]

        // act
        let incoming = target.incomingCalls()

        // assert
        @Expect(incoming.size, 1)
        @Expect(incoming[0].resolution, "inferred-operator")
        @Expect(incoming[0].callee.identity, target.identity)
    }

    @TestCase
    func backquotedGenericNamesUseCanonicalSpellingForUsages(): Unit {
        // arrange
        let fixture = Fixture.parse(
            "func f<`T`>(x: `T`): `T` { x }\nfunc outer() { func local<`U`>(x: `U`): `U` { x } }"
        )
        let db = fixture.database()
        let written = fixture.files[0]
        let analysis = SemanticAnalysis(db)
        let first =
            analysis
                .at(written.fileId, written.text.indexOf("`T`").getOrThrow())
                .getOrThrow()
                .definitions
                .getOrThrow()[0]
        let second =
            analysis
                .at(written.fileId, written.text.indexOf("`U`").getOrThrow())
                .getOrThrow()
                .definitions
                .getOrThrow()[0]

        // act
        let typeUses = first.usages().getOrThrow().entries
        let localUses = second.usages().getOrThrow().entries

        // assert
        @Expect(typeUses.size, 3)
        @Expect(localUses.size, 3)
        @Expect(typeUses.filter { entry => entry.isDeclaration }.size, 1)
        @Expect(localUses.filter { entry => entry.isDeclaration }.size, 1)
    }

    @TestCase
    func propertyAccessorCallsBelongToThePropertyIdentity(): Unit {
        // arrange
        let fixture = Fixture.parse(
            "func tar$0get(): Int64 { 1 }\nclass C { prop value: Int64 { get() { target() } set(v) { target() } } }"
        )
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let target =
            SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]

        // act
        let incoming = target.incomingCalls()
        let uses = target.usages().getOrThrow().entries.filter { use => !use.isDeclaration }

        // assert
        @Expect(incoming.size, 2)
        @Expect(uses.size, 2)
        @Expect(incoming.all { edge => semanticOriginText(edge.caller) == ["value"] })
        @Expect(incoming[0].caller.identity, incoming[1].caller.identity)
        @Expect(uses.all { use => match (use.owner) {
            case ObjectOwner(owner) => owner.identity == incoming[0].caller.identity
            case _ => false
        } })
    }
}
