package loupe

import std.collection.*
import std.sync.AtomicBool
import std.unittest.*
import std.unittest.testmacro.*
import calca.CancelledException
import cjsyntax.SyntaxKind
import ginkgo.TextRange
import rope.Rope
import loupe.db.*
import loupe.fixture.*
import loupe.hir.*
import loupe.vfs.PathInterner

func syntaxNode(root: SemanticSyntaxElement, kind: SyntaxKind): SemanticSyntaxElement {
    let found =
        root.descendants().iterator() |>
            filter { node: SemanticSyntaxElement => !node.isToken() && node.kind() == kind } |>
            first
    found ?? throw FixtureException("missing syntax ${kind}")
}

func syntaxOriginNode(origin: SemanticSyntaxOrigin): SemanticSyntaxElement {
    match (origin) {
        case SourceSyntax(node) => node
        case _ => throw FixtureException("expected written syntax")
    }
}

@Test
class SemanticSyntaxTest {
    @TestCase
    func traversalPreservesModifiersAnnotationsImportsAndTrivia(): Unit {
        // arrange
        const TEXT =
            "package m\nimport std.core.*\n// я😀\n@Deprecated public func f(x: Int64) { x }\n"
        let fixture = Fixture.parse(TEXT)
        let db = fixture.database()
        let analysis = SemanticAnalysis(db)

        // act
        let tree = analysis.syntaxAt(fixture.files[0].fileId).getOrThrow()
        let root = tree.root()
        let elements = root.descendants()
        let tokens = elements.filter { it => it.isToken() }
        let decl = syntaxNode(root, SyntaxKind.FuncDecl)
        let targets = decl.mappings()

        // assert
        @Expect(root.text(), TEXT)
        @Expect(String.join(tokens.map { it => it.text() }), TEXT)
        @Expect(elements.any { it => it.kind() == SyntaxKind.ImportDecl })
        @Expect(elements.any { it => it.kind() == SyntaxKind.Annotation })
        @Expect(tokens.any { it => it.kind() == SyntaxKind.PublicKw })
        @Expect(tokens.any { it => it.kind() == SyntaxKind.LineComment && it.text() == "// я😀" })
        @Expect(tree.errors().isEmpty())
        @Assert(targets.size, 1)
        @Expect(syntaxOriginNode(targets[0].object.syntaxOrigins()[0]).kind(), SyntaxKind.FuncDecl)
        @Expect(syntaxOriginNode(targets[0].object.syntaxOrigins()[0]).text(), decl.text())
        @Expect(decl.parent().getOrThrow().kind(), root.kind())
        @Expect(String.join(root.children().map { it => it.text() }), TEXT)
    }

    @TestCase
    func exactMappingsDoNotBorrowAncestorsAndAllArenasRoundTrip(): Unit {
        // arrange
        let fixture = Fixture.parse(
            "func f(x: Int64) { let (a, b) = (1, 2); let c: Bool = true; a }"
        )
        let db = fixture.database()
        let analysis = SemanticAnalysis(db)
        let root = analysis.syntaxAt(fixture.files[0].fileId).getOrThrow().root()

        // act
        let all = root.descendants()
        let name =
            all.iterator() |>
                filter {
                    it: SemanticSyntaxElement =>
                    !it.isToken() && it.kind() == SyntaxKind.NameRef && it.text() == "a"
                } |>
                first
        let mappings = all.flatMap { it => it.mappings() }

        // assert
        @Expect(name.getOrThrow().mappings().isEmpty())
        @Expect(all.filter { it => it.isToken() }.all { it => it.mappings().isEmpty() })
        @Expect(mappings.any { it => match (it.object.identity) { case ExpressionIdentity(_, _) => true; case _ => false } })
        @Expect(mappings.any { it => match (it.object.identity) { case PatternIdentity(_, _) => true; case _ => false } })
        @Expect(mappings.any { it => match (it.object.identity) { case LocalIdentity(_, _) => true; case _ => false } })
        @Expect(mappings.any { it => match (it.object.identity) { case SignatureTypeIdentity(_, _) => true; case _ => false } })
        @Expect(mappings.any { it => match (it.object.identity) { case BodyTypeIdentity(_, _) => true; case _ => false } })
        for (mapping in mappings) {
            let back = syntaxOriginNode(mapping.object.syntaxOrigins()[0])
            let matches =
                back.mappings().any { it => it.object.identity == mapping.object.identity }
            if (!matches) {
                let category =
                    match (mapping.object.identity) {
                        case NamedIdentity(_) => "named"
                        case ExpressionIdentity(_, id) => "expr ${id.index}"
                        case PatternIdentity(_, id) => "pat ${id.index}"
                        case LocalIdentity(_, id) => "local ${id.index}"
                        case SignatureTypeIdentity(_, id) => "signature type ${id.index}"
                        case BodyTypeIdentity(_, id) => "body type ${id.index}"
                    }
                throw FixtureException("roundtrip ${category}: ${back.kind()} '${back.text()}'")
            }
        }
    }

    @TestCase[chain in ["c?.x", "c?.next?.x"]]
    func optionalChainReturnsWrittenAndDesugaredValuesInArenaOrder(chain: String): Unit {
        // arrange
        let fixture = Fixture.parse(
            "class C { let x = 1; let next: ?C = None }\nfunc f(c: ?C) { ${chain}$0 }"
        )
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)
        let root = analysis.syntaxAt(at.fileId).getOrThrow().root()
        let chainNode =
            root.descendants().iterator() |>
                filter {
                    it: SemanticSyntaxElement =>
                    it.kind() == SyntaxKind.MemberAccessExpr && it.text() == chain
                } |>
                first
        let count = if (chain == "c?.x") { 2 } else { 3 }

        // act
        let mappings =
            chainNode
                .getOrThrow()
                .mappings()
                .filter {
                    it =>
                    match (it.object.identity) {
                        case ExpressionIdentity(_, _) => true;
                        case _ => false
                    }
                }
        let position = analysis.at(at.fileId, at.offset).getOrThrow()

        // assert
        @Assert(mappings.size, count)
        @Expect(match (mappings[0].role) { case DirectSyntaxMapping => true; case _ => false })
        @Expect(match (mappings[mappings.size - 1].role) { case DesugaredSyntaxMapping => true; case _ => false })
        @Expect(position.objects.any { it => it.identity == mappings[0].object.identity })
        for (mapping in mappings) {
            @Expect(syntaxOriginNode(mapping.object.syntaxOrigins()[0]).text(), chain)
        }
    }

    @TestCase
    func syntheticAndUnavailableHaveDistinctReverseSyntax(): Unit {
        // arrange
        let fixture = Fixture.parse("class C { let x = 1 }\nfunc f(c: ?C) { c$0?.x }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)
        let owner =
            match (analysis.at(at.fileId, at.offset).getOrThrow().owner.getOrThrow().identity) {
                case NamedIdentity(DeclDef(id)) => id
                case _ => throw FixtureException("no owner")
            }
        let map = bodyWithSourceMap(db, owner).sourceMap
        let synthetic =
            (0..map.exprs.size).iterator() |>
                filter { i: Int64 => map.exprs[i] == BodyOrigin.SyntheticSource } |>
                first

        // act
        let generated = analysis
            .object(ExpressionIdentity(owner, ExprId(synthetic.getOrThrow())))
            .syntaxOrigins()
        let unavailable = analysis
            .object(ExpressionIdentity(owner, ExprId(map.exprs.size)))
            .syntaxOrigins()

        // assert
        @Expect(match (generated[0]) { case SyntheticSyntax => true; case _ => false })
        @Expect(match (unavailable[0]) { case UnavailableSyntax => true; case _ => false })
    }

    @TestCase
    func pointersRejectIdenticalRangesInForeignFilesAndAnalyses(): Unit {
        // arrange
        let fixture = Fixture.parse("//- /a.cj\nfunc f() {}\n//- /b.cj\nfunc f() {}\n")
        let db = fixture.database()
        let analysis = SemanticAnalysis(db)
        let firstTree = analysis.syntaxAt(fixture.files[0].fileId).getOrThrow()
        let secondTree = analysis.syntaxAt(fixture.files[1].fileId).getOrThrow()
        let pointer = firstTree.root().pointer().getOrThrow()
        let otherAnalysisTree = SemanticAnalysis(db).syntaxAt(fixture.files[0].fileId).getOrThrow()

        // act
        let same = analysis.syntaxAt(fixture.files[0].fileId).getOrThrow().resolve(pointer)

        // assert
        @Expect(same.getOrThrow().text(), firstTree.root().text())
        @Expect(firstTree.root().location().fullRange, secondTree.root().location().fullRange)
        @AssertThrows[IllegalArgumentException](secondTree.resolve(pointer))
        @AssertThrows[IllegalArgumentException](otherAnalysisTree.resolve(pointer))
    }

    @TestCase
    func retainedTreesTokensErrorsAndPointersRejectWritesEvenWithIdenticalShape(): Unit {
        // arrange
        let fixture = Fixture.parse("func f() { let $0")
        let db = fixture.database()
        let fileId = fixture.files[0].fileId
        let analysis = SemanticAnalysis(db)
        let tree = analysis.syntaxAt(fileId).getOrThrow()
        let root = tree.root()
        let pointer = root.pointer().getOrThrow()
        let token =
            root.descendants().iterator() |> filter { it: SemanticSyntaxElement => it.isToken() } |>
                first
        let error = tree.errors()[0]
        let copy = root.text()
        let errorRange = error.range()

        // act
        db.setFileText(fileId, Rope(copy.replace("f", "g")))
        let fresh = SemanticAnalysis(db).syntaxAt(fileId).getOrThrow()

        // assert
        @Expect(errorRange.end <= copy.size)
        @AssertThrows[CancelledException](tree.root())
        @AssertThrows[CancelledException](tree.errors())
        @AssertThrows[CancelledException](root.text())
        @AssertThrows[CancelledException](root.children())
        @AssertThrows[CancelledException](root.descendants())
        @AssertThrows[CancelledException](root.mappings())
        @AssertThrows[CancelledException](root.pointer())
        @AssertThrows[CancelledException](token.getOrThrow().kind())
        @AssertThrows[CancelledException](token.getOrThrow().text())
        @AssertThrows[CancelledException](token.getOrThrow().parent())
        @AssertThrows[CancelledException](error.range())
        @AssertThrows[CancelledException](error.message())
        @AssertThrows[CancelledException](error.error())
        @AssertThrows[CancelledException](fresh.resolve(pointer))
    }

    @TestCase
    func requestCancellationInvalidatesSyntaxViews(): Unit {
        // arrange
        let fixture = Fixture.parse("func f() {}")
        let db = fixture.database()
        let stop = AtomicBool(false)
        let analysis = SemanticAnalysis(db.snapshot(cancelledBy: { => stop.load() }))
        let tree = analysis.syntaxAt(fixture.files[0].fileId).getOrThrow()
        let root = tree.root()

        // act
        stop.store(true)

        // assert
        @AssertThrows[CancelledException](root.kind())
        @AssertThrows[CancelledException](root.isToken())
        @AssertThrows[CancelledException](root.location())
        @AssertThrows[CancelledException](analysis.syntaxAt(fixture.files[0].fileId))
    }

    @TestCase
    func expressionExpansionAliasesRoundTripWithoutLosingProvenance(): Unit {
        // arrange
        let (db, file) = expansionDatabase("package m\nimport m.ms.*\nfunc f() { @A(1) + @M(1) }")
        const OUTPUT = "1"
        let call = answer(db, file, "A", OUTPUT, [MappedSpan(TextRange(0, 1), SpanOrigin.FromCall)])
        let otherCall = answer(
            db,
            file,
            "M",
            OUTPUT,
            [MappedSpan(TextRange(0, 1), SpanOrigin.FromCall)]
        )
        let analysis = SemanticAnalysis(db)
        let tree = analysis.syntax(ItemFile.Expansion(call)).getOrThrow()
        let other = analysis.syntax(ItemFile.Expansion(otherCall)).getOrThrow()
        let literal = syntaxNode(tree.root(), SyntaxKind.Literal)

        // act
        let mapping = literal.mappings()[0]
        let origins = mapping.object.syntaxOrigins()
        let source = analysis.syntax(ItemFile.Source(file)).getOrThrow()
        let callSite = syntaxNode(source.root(), SyntaxKind.MacroExpandExpr)
        let aliases = callSite.mappings()

        // assert
        @Expect(origins.size, 2)
        @Expect(syntaxOriginNode(origins[0]).location().file, ItemFile.Expansion(call))
        @Expect(syntaxOriginNode(origins[1]).location().file, ItemFile.Source(file))
        @Expect(aliases.any { it => it.object.identity == mapping.object.identity && match (it.role) { case ExpansionAliasMapping => true; case _ => false } })
        @Expect(syntaxNode(other.root(), SyntaxKind.Literal).mappings()[0].object.identity != mapping.object.identity)
        @Expect(literal.location().source().isNone())
        @AssertThrows[IllegalArgumentException](other.resolve(literal.pointer().getOrThrow()))
    }

    @TestCase
    func declarationExpansionAndInactiveSyntaxRemainTraversable(): Unit {
        // arrange
        let (db, _, call, _) = answeredM()
        let analysis = SemanticAnalysis(db)
        let root = analysis.syntax(ItemFile.Expansion(call)).getOrThrow().root()

        // act
        let declaration = syntaxNode(root, SyntaxKind.ClassDecl)
        let mapping = declaration.mappings()[0]

        // assert
        @Expect(syntaxOriginNode(mapping.object.syntaxOrigins()[0]).location().file, ItemFile.Expansion(call))
        @Expect(declaration.location().source().isSome())

        // arrange
        let inactive = Fixture.parse("//- /main.cj inactive=windows\nfunc f() { 1 }")
        let inactiveDb = inactive.database()

        // act
        let syntax = SemanticAnalysis(inactiveDb).syntaxAt(inactive.files[0].fileId).getOrThrow()

        // assert
        @Expect(syntaxNode(syntax.root(), SyntaxKind.FuncDecl).text(), "func f() { 1 }")
    }
    @TestCase
    func equalPhysicalPathsInScriptContextDoNotSharePointersOrMappings(): Unit {
        // arrange
        let fixture = Fixture.parse(
            "//- /lib.cj module=m package=m\npackage m\npublic func f() { 1 }"
        )
        let ordinary = fixture.projectModel().modules[0]
        let script = ModuleModel(
            ordinary.name,
            ordinary.root,
            ordinary.packages,
            resolutionScope: "script"
        )
        let db = AnalysisDatabase()
        let paths = PathInterner()
        db.setProject(ProjectModel(Cfg([]), [ordinary, script]), paths)
        let written = fixture.files[0]
        let fileId = paths.intern(written.path)
        db.setFileText(fileId, Rope(written.text))
        let modules = db.project().getOrThrow().modules(db)
        let plain = db.sourceFile(fileId, context: modules[0].packages(db)[0]).getOrThrow()
        let scoped = db.sourceFile(fileId, context: modules[1].packages(db)[0]).getOrThrow()
        let analysis = SemanticAnalysis(db)
        let first = analysis.syntax(ItemFile.Source(plain)).getOrThrow()
        let second = analysis.syntax(ItemFile.Source(scoped)).getOrThrow()

        // act
        let firstNode = syntaxNode(first.root(), SyntaxKind.FuncDecl)
        let secondNode = syntaxNode(second.root(), SyntaxKind.FuncDecl)
        let firstObject = firstNode.mappings()[0].object
        let secondObject = secondNode.mappings()[0].object

        // assert
        @Expect(firstNode.location().fullRange, secondNode.location().fullRange)
        @Expect(firstObject.identity != secondObject.identity)
        @Expect(syntaxOriginNode(secondObject.syntaxOrigins()[0]).location().file, ItemFile.Source(scoped))
        @AssertThrows[IllegalArgumentException](second.resolve(firstNode.pointer().getOrThrow()))
    }

    @TestCase
    func genericParametersAndCheckedBinaryDeclarationsRoundTrip(): Unit {
        // arrange
        let fixture = Fixture.parse(
            "func f<T>(x: T) {}\nfunc g() { func h<U>(x: U) {}; print$0ln(1) }"
        )
        let db = fixture.database(
            binaries: [stdCjoRead("std.core", stdCjo("std.core"))],
            models: [stdWithSources(["std.core"])]
        )
        let analysis = SemanticAnalysis(db)
        let at = fixture.cursor.getOrThrow()
        let root = analysis.syntaxAt(at.fileId).getOrThrow().root()

        // act
        let params = root.descendants().filter { it => it.kind() == SyntaxKind.TypeParam }
        let binary = analysis.at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]
        let binaryNode = syntaxOriginNode(binary.syntaxOrigins()[0])

        // assert
        @Assert(params.size, 2)
        for (param in params) {
            @Assert(param.mappings().size, 1)
            @Expect(syntaxOriginNode(param.mappings()[0].object.syntaxOrigins()[0]).text(), param.text())
        }
        @Expect(binaryNode.location().kind(), SemanticSourceKind.AttachedSource)
        @Expect(binaryNode.mappings().any { it => it.object.identity == binary.identity })

        // arrange
        let noSource = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let unavailable = SemanticAnalysis(noSource)
        let target = unavailable.at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]
        let file =
            match (target.identity) {
                case NamedIdentity(DeclDef(id)) => id.file(noSource)
                case _ => throw FixtureException("expected binary declaration")
            }

        // act
        let tree = unavailable.syntax(file)
        let origins = target.syntaxOrigins()

        // assert
        @Expect(tree.isNone())
        @Expect(match (origins[0]) { case UnavailableSyntax => true; case _ => false })
    }

    @TestCase
    func parserRecoveryAndUnavailableExpansionsAreExplicit(): Unit {
        // arrange
        const TEXT = "func f() { let "
        let fixture = Fixture.parse(TEXT)
        let db = fixture.database()
        let analysis = SemanticAnalysis(db)

        // act
        let tree = analysis.syntaxAt(fixture.files[0].fileId).getOrThrow()
        let errors = tree.errors()

        // assert
        @Expect(tree.root().text(), TEXT)
        @Assert(!errors.isEmpty())
        @Expect(errors.all { it => it.range().end <= TEXT.size && !it.message().isEmpty() })
        @Expect(errors.any { it => match (it.error()) { case Expected(_) => true; case _ => false } })

        // arrange
        let (macroDb, file) = expansionDatabase("package m\nimport m.ms.*\nfunc f() { @A(1) }")
        let request = requestFor(macroDb, file, "A")
        let unanswered = SemanticAnalysis(macroDb)

        // act
        let missing = unanswered.syntax(ItemFile.Expansion(request.call))

        // assert
        @Expect(missing.isNone())
    }
    @TestCase
    func equalPhysicalAndExpansionTreesStillRejectForeignPointers(): Unit {
        // arrange
        let (db, file) = expansionDatabase("package m\nimport m.ms.*\n@M[x] class C {}")
        let text = file.text(db).toString()
        let call = answer(
            db,
            file,
            "M",
            text,
            [MappedSpan(TextRange(0, text.size), SpanOrigin.FromCall)]
        )
        let analysis = SemanticAnalysis(db)
        let physical = analysis.syntax(ItemFile.Source(file)).getOrThrow()
        let generated = analysis.syntax(ItemFile.Expansion(call)).getOrThrow()

        // act
        let pointer = physical.root().pointer().getOrThrow()

        // assert
        @Expect(physical.root().kind(), generated.root().kind())
        @Expect(physical.root().text(), generated.root().text())
        @Expect(physical.root().location().fullRange, generated.root().location().fullRange)
        @AssertThrows[IllegalArgumentException](generated.resolve(pointer))
    }

    @TestCase
    func statementExpansionBindingsTypesAndGenericsRoundTrip(): Unit {
        // arrange
        let (db, file) = expansionDatabase("package m\nimport m.ms.*\nfunc f() { @A(1) }")
        const OUTPUT = "let v: Int64 = 1; func h<T>(x: T) {}; v"
        let call = answer(
            db,
            file,
            "A",
            OUTPUT,
            [MappedSpan(TextRange(0, OUTPUT.size), SpanOrigin.FromCall)]
        )
        let analysis = SemanticAnalysis(db)
        let tree = analysis.syntax(ItemFile.Expansion(call)).getOrThrow()

        // act
        let mappings = tree.root().descendants().flatMap { it => it.mappings() }

        // assert
        @Expect(mappings.any { it => match (it.object.identity) { case LocalIdentity(_, _) => true; case _ => false } })
        @Expect(mappings.any { it => match (it.object.identity) { case BodyTypeIdentity(_, _) => true; case _ => false } })
        @Expect(mappings.any { it => match (it.object.identity) { case NamedIdentity(TypeParamDef(_)) => true; case _ => false } })
        for (mapping in mappings) {
            let node = syntaxOriginNode(mapping.object.syntaxOrigins()[0])
            @Expect(node.location().file, ItemFile.Expansion(call))
            @Expect(node.mappings().any { it => it.object.identity == mapping.object.identity })
        }
    }
}
