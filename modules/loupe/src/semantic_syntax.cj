package loupe

import std.collection.{ArrayList, collectArray, map}
import cjsyntax.{CjParse, CjSyntaxElement, CjSyntaxNode, SyntaxKind, message as parseMessage}
import cjsyntax.ast.{Decl, TypeParam}
import ginkgo.{SyntaxElement, SyntaxNodePtr, TextRange}
import ginkgo.parsing.{ParseError, SyntaxError}
import py_interop.*
import py_interop.internal_macros.DerivePython
import loupe.hir.{
    BodyOrigin,
    BodySource,
    DefId,
    ItemFile,
    LocalId,
    MacroCallId,
    PatId,
    TypeRefId,
    bodyWithSourceMap,
    canonicalDef,
    expansionParse,
    signatureWithSourceMap,
    sourceDefOf,
    syntaxOf
}
import loupe.syntax.parse
import loupe.vfs.FileId

/**
 * A request-owned lossless tree. Every view operation checks the originating analysis revision.
 * Never store this tree or its elements in tracked results (A13); retain pointer() instead.
 */
@DerivePython
public class SemanticSyntaxTree {
    @PyIgnore
    let analysis: SemanticAnalysis
    @PyIgnore
    let file: ItemFile
    @PyIgnore
    let parsed: CjParse

    @PyIgnore
    init(analysis: SemanticAnalysis, file: ItemFile, parsed: CjParse) {
        this.analysis = analysis
        this.file = file
        this.parsed = parsed
    }

    public func root(): SemanticSyntaxElement {
        analysis.db.unwindIfCancelled()
        element(SyntaxElement.Node(parsed.syntaxNode()))
    }

    public func errors(): Array<SemanticSyntaxError> {
        analysis.db.unwindIfCancelled()
        parsed.errors.map { error => SemanticSyntaxError(analysis, error) }
    }

    /**
     * Resolves only pointers issued by this analysis and contextual file, even when another
     * tree has identical kind/range. Stale pointers throw CancelledException; foreign ones
     * throw IllegalArgumentException before raw pointer resolution.
     */
    public func resolve(pointer: SemanticSyntaxPointer): ?SemanticSyntaxElement {
        pointer.analysis.db.unwindIfCancelled()
        analysis.db.unwindIfCancelled()
        if (!refEq(pointer.analysis, analysis) || pointer.file != file) {
            throw IllegalArgumentException(
                "syntax pointer belongs to another analysis or contextual file"
            )
        }
        pointer.ptr.tryToNode(parsed.syntaxNode()).map { node => element(SyntaxElement.Node(node)) }
    }

    @PyIgnore
    func element(raw: CjSyntaxElement): SemanticSyntaxElement {
        SemanticSyntaxElement(this, raw)
    }
}

/**
 * A tree-free node handle qualified by its analysis and contextual file/expansion.
 * Construction is confined to checked views; raw kind/range pairs cannot forge provenance.
 */
@DerivePython
public class SemanticSyntaxPointer {
    @PyIgnore
    let analysis: SemanticAnalysis
    @PyIgnore
    let file: ItemFile
    @PyIgnore
    let ptr: SyntaxNodePtr<SyntaxKind>

    @PyIgnore
    init(analysis: SemanticAnalysis, file: ItemFile, ptr: SyntaxNodePtr<SyntaxKind>) {
        this.analysis = analysis
        this.file = file
        this.ptr = ptr
    }
}

/**
 * A node or token, including trivia and recovery nodes. Copied text/ranges describe this revision;
 * retained elements reject operations after a write. Children/descendants preserve source order.
 */
@DerivePython
public class SemanticSyntaxElement {
    @PyIgnore
    let tree: SemanticSyntaxTree
    @PyIgnore
    let raw: CjSyntaxElement

    @PyIgnore
    init(tree: SemanticSyntaxTree, raw: CjSyntaxElement) {
        this.tree = tree
        this.raw = raw
    }

    public func kindName(): String {
        kind().toString()
    }

    @PyIgnore
    public func kind(): SyntaxKind {
        tree.analysis.db.unwindIfCancelled()
        raw.kind
    }

    public func isToken(): Bool {
        tree.analysis.db.unwindIfCancelled()
        raw.asToken().isSome()
    }

    public func text(): String {
        tree.analysis.db.unwindIfCancelled()
        raw.toString()
    }

    public func location(): SemanticLocation {
        tree.analysis.db.unwindIfCancelled()
        tree.analysis.location(tree.file, raw.textRange, raw.textRange)
    }

    public func parent(): ?SemanticSyntaxElement {
        tree.analysis.db.unwindIfCancelled()
        raw.parent.map { node => tree.element(SyntaxElement.Node(node)) }
    }

    public func children(): Array<SemanticSyntaxElement> {
        tree.analysis.db.unwindIfCancelled()
        let node = raw.asNode() ?? return []
        node.childrenWithTokens() |> map { child: CjSyntaxElement => tree.element(child) } |>
            collectArray
    }

    /**
     * Preorder including this element. No ancestor mapping or automatic macro descent occurs.
     */
    public func descendants(): Array<SemanticSyntaxElement> {
        tree.analysis.db.unwindIfCancelled()
        let node = raw.asNode() ?? return [this]
        let found = ArrayList<SemanticSyntaxElement>()
        for (child in node.descendantsWithTokens()) {
            tree.analysis.db.unwindIfCancelled()
            found.add(tree.element(child))
        }
        found.toArray()
    }

    /**
     * Nodes have pointers; tokens remain checked views belonging to their containing tree.
     */
    public func pointer(): ?SemanticSyntaxPointer {
        tree.analysis.db.unwindIfCancelled()
        raw
            .asNode()
            .map { node => SemanticSyntaxPointer(tree.analysis, tree.file, SyntaxNodePtr(node)) }
    }

    /**
     * Exact node mappings, never a nearest mapped ancestor. Tokens/unmapped nodes return [];
     * unavailable trees return none from SemanticAnalysis.syntax. Declaration, signature type,
     * expression, pattern, local and body type mappings appear in that order, each in arena
     * order. Macro aliases retain their call-site role and expansion object identity.
     */
    public func mappings(): Array<SemanticSyntaxMapping> {
        tree.analysis.db.unwindIfCancelled()
        exactSyntaxMappings(tree.analysis, tree.file, raw.asNode() ?? return [])
    }
}

/**
 * Parser recovery evidence bound to the tree's revision, including zero-width ranges.
 */
@DerivePython
public class SemanticSyntaxError {
    @PyIgnore
    let analysis: SemanticAnalysis
    @PyIgnore
    let raw: SyntaxError<SyntaxKind>

    @PyIgnore
    init(analysis: SemanticAnalysis, raw: SyntaxError<SyntaxKind>) {
        this.analysis = analysis
        this.raw = raw
    }

    public func range(): TextRange {
        analysis.db.unwindIfCancelled()
        raw.range
    }

    @PyIgnore
    public func error(): ParseError<SyntaxKind> {
        analysis.db.unwindIfCancelled()
        raw.error
    }

    public func message(): String {
        analysis.db.unwindIfCancelled()
        parseMessage(raw.error)
    }
}

/**
 * Direct mappings include declarations/types/bindings and the first written expression.
 * Later expressions of the same syntax are desugared values; aliases link call sites to
 * expansion objects whose canonical syntax remains inside the expansion.
 */
@DerivePython
public enum SemanticSyntaxRole {
    | DirectSyntaxMapping
    | DesugaredSyntaxMapping
    | ExpansionAliasMapping
}

/**
 * One exact syntax-to-HIR relationship. Several relationships may share either endpoint.
 */
@DerivePython
public class SemanticSyntaxMapping {
    SemanticSyntaxMapping(public let object: SemanticObject, public let role: SemanticSyntaxRole) {}
}

/**
 * Exact syntax, synthetic HIR and unavailable source remain distinct when traversing back.
 */
@DerivePython
public enum SemanticSyntaxOrigin {
    | SourceSyntax(SemanticSyntaxElement)
    | SyntheticSyntax
    | UnavailableSyntax
}

@DerivePython
extend SemanticAnalysis {
    /**
     * Lossless source in the editor's preferred context; none for an unavailable file.
     */
    public func syntaxAt(fileId: FileId): ?SemanticSyntaxTree {
        db.unwindIfCancelled()
        syntax(ItemFile.Source(db.sourceFile(fileId) ?? return None))
    }

    /**
     * Preserves explicit source/expansion context. Binary/compiler declarations have no tree;
     * missing/failed macro output is unavailable, rather than a successful empty expansion.
     * ItemFile must originate from this database/revision, as for inFile().
     */
    public func syntax(file: ItemFile): ?SemanticSyntaxTree {
        db.unwindIfCancelled()
        let parsed =
            match (file) {
                case Source(source) => parse(db, source)
                case Expansion(call) =>
                    if (expandedMacro(db, call).isNone()) {
                        return None
                    }
                    expansionParse(db, call)
                case _ => return None
            }
        SemanticSyntaxTree(this, file, parsed)
    }

    @PyIgnore
    func syntaxSource(file: ItemFile, ptr: SyntaxNodePtr<SyntaxKind>): SemanticSyntaxOrigin {
        let tree = syntax(file) ?? return UnavailableSyntax
        let node = ptr.tryToNode(tree.parsed.syntaxNode()) ?? return UnavailableSyntax
        SourceSyntax(tree.element(SyntaxElement.Node(node)))
    }
}

@DerivePython
extend SemanticObject {
    /**
     * Written syntax followed by distinct expansion call-site aliases in lowering order.
     * Synthetic/unavailable nodes stay explicit. The canonical origin returned by origins()
     * is unchanged; this traversal additionally exposes the many-to-one expansion bridge.
     */
    public func syntaxOrigins(): Array<SemanticSyntaxOrigin> {
        let db = analysis.db
        db.unwindIfCancelled()
        match (identity) {
            case NamedIdentity(Definition.DeclDef(id)) =>
                let source = sourceDefOf(db, id) ?? id
                if (let Some(node) <- itemNodeOf(db, source)) {
                    return [analysis.syntaxSource(source.file(db), SyntaxNodePtr(node))]
                }
            case ExpressionIdentity(owner, id) =>
                let sources = bodyWithSourceMap(db, owner).sourceMap.sourcesOfExpr(id)
                if (!sources.isEmpty()) {
                    return sources
                        .map {
                            source =>
                            analysis.syntaxSource(source.inFile(owner.file(db)), source.ptr)
                        }
                }
            case SignatureTypeIdentity(owner, id) =>
                let ptr =
                    signatureWithSourceMap(db, owner)
                        .sourceMap
                        .ptrs
                        .get(id.index)
                        .flatMap { it => it } ??
                        return [UnavailableSyntax]
                return [analysis.syntaxSource(owner.file(db), ptr)]
            case PatternIdentity(owner, id) =>
                return bodySyntax(owner, bodyWithSourceMap(db, owner).sourceMap.pats.get(id.index))
            case LocalIdentity(owner, id) =>
                return bodySyntax(
                    owner,
                    bodyWithSourceMap(db, owner).sourceMap.locals.get(id.index)
                )
            case BodyTypeIdentity(owner, id) =>
                return bodySyntax(owner, bodyWithSourceMap(db, owner).sourceMap.types.get(id.index))
            case _ => ()
        }
        origins()
            .map {
                origin =>
                match (origin) {
                    case SourceOrigin(location) => locationSyntax(location)
                    case SyntheticOrigin => SyntheticSyntax
                    case UnavailableOrigin => UnavailableSyntax
                }
            }
    }

    private func bodySyntax(owner: DefId, origin: ?BodyOrigin): Array<SemanticSyntaxOrigin> {
        match (origin) {
            case Some(WrittenSource(source)) =>
                [analysis.syntaxSource(source.inFile(owner.file(analysis.db)), source.ptr)]
            case Some(SyntheticSource) => [SyntheticSyntax]
            case None => [UnavailableSyntax]
        }
    }

    private func locationSyntax(location: SemanticLocation): SemanticSyntaxOrigin {
        let tree = analysis.syntax(location.file) ?? return UnavailableSyntax
        for (
            node in tree.parsed.syntaxNode().descendants() where node.textRange ==
                location.fullRange
        ) {
            return SourceSyntax(tree.element(SyntaxElement.Node(node)))
        }
        UnavailableSyntax
    }
}

/**
 * Uses the owning declaration's source maps without treating coordinates as identity.
 * An expression expansion contributes to its caller's body instead of having an item.
 */
func exactSyntaxMappings(
    analysis: SemanticAnalysis,
    file: ItemFile,
    node: CjSyntaxNode
): Array<SemanticSyntaxMapping> {
    let db = analysis.db
    let (_, ids) = syntaxOf(db, file) ?? return []
    let ptr = SyntaxNodePtr(node)
    let found = ArrayList<SemanticSyntaxMapping>()
    if (Decl.cast(node).isSome() && let Some(id) <- ids.idOf(ptr)) {
        found.add(
            SemanticSyntaxMapping(
                analysis.object(
                    NamedIdentity(Definition.DeclDef(canonicalDef(db, DefId(db, file, id))))
                ),
                DirectSyntaxMapping
            )
        )
    }
    let item = itemAround(db, file, node)
    let expansion =
        match (file) {
            case Expansion(call) where item.isNone() => Some(call)
            case _ => None<MacroCallId>
        }
    let owner =
        item ??
            expansion.flatMap { call => bodyOfExpressionExpansion(db, call) } ??
                return found.toArray()
    if (
        let Some(mapping) <- genericSyntaxMapping(analysis, file, node, owner, expansion: expansion)
    ) {
        found.add(mapping)
    }
    let source = BodySource(ptr, expansion: expansion)
    let signature = signatureWithSourceMap(db, owner).sourceMap
    if (expansion.isNone()) {
        for (i in 0..signature.ptrs.size where signature.ptrs[i] == ptr) {
            found.add(
                SemanticSyntaxMapping(
                    analysis.object(SignatureTypeIdentity(owner, TypeRefId(i))),
                    DirectSyntaxMapping
                )
            )
        }
    }
    found.add(all: bodySyntaxMappings(analysis, owner, source))
    found.toArray()
}

/**
 * A generic declaration retains its real item or local-function binder.
 */
func genericSyntaxMapping(
    analysis: SemanticAnalysis,
    file: ItemFile,
    node: CjSyntaxNode,
    owner: DefId,
    expansion!: ?MacroCallId
): ?SemanticSyntaxMapping {
    let param = TypeParam.cast(node) ?? return None
    let target =
        typeParamTargetIn(analysis.db, file, param, Some(owner), expansion: expansion) ??
            return None
    SemanticSyntaxMapping(
        analysis.object(NamedIdentity(Definition.TypeParamDef(target))),
        DirectSyntaxMapping
    )
}

/**
 * A body's exact relationships retain arena order independently of positional selection.
 */
func bodySyntaxMappings(
    analysis: SemanticAnalysis,
    owner: DefId,
    source: BodySource
): Array<SemanticSyntaxMapping> {
    let db = analysis.db
    let found = ArrayList<SemanticSyntaxMapping>()
    let body = bodyWithSourceMap(db, owner).sourceMap
    for (id in body.exprsAtSource(source)) {
        let role =
            if (body.exprs.get(id.index) != Some(BodyOrigin.WrittenSource(source))) {
                ExpansionAliasMapping
            } else if (body.exprAtSource(source) == id) {
                DirectSyntaxMapping
            } else {
                DesugaredSyntaxMapping
            }
        found.add(SemanticSyntaxMapping(analysis.object(ExpressionIdentity(owner, id)), role))
    }
    for (i in 0..body.pats.size where body.pats[i] == BodyOrigin.WrittenSource(source)) {
        found.add(
            SemanticSyntaxMapping(
                analysis.object(PatternIdentity(owner, PatId(i))),
                DirectSyntaxMapping
            )
        )
    }
    for (i in 0..body.locals.size where body.locals[i] == BodyOrigin.WrittenSource(source)) {
        found.add(
            SemanticSyntaxMapping(
                analysis.object(LocalIdentity(owner, LocalId(i))),
                DirectSyntaxMapping
            )
        )
    }
    for (i in 0..body.types.size where body.types[i] == BodyOrigin.WrittenSource(source)) {
        found.add(
            SemanticSyntaxMapping(
                analysis.object(BodyTypeIdentity(owner, TypeRefId(i))),
                DirectSyntaxMapping
            )
        )
    }
    found.toArray()
}
