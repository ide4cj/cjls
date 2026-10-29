package cjmcp

import std.collection.ArrayList
import std.fs.Path
import ginkgo.TextRange
import loupe.Reference as AnalysisReference
import loupe.completionDetails as nativeCompletionDetails
import loupe.{
    CompletionItem,
    CompletionResult,
    ExpandedFile,
    ExpandedMacro,
    Fold,
    FoundSymbol,
    HighlightedRange,
    HoverItem,
    MacroCallAt,
    NavigationTarget,
    RelatedHighlight,
    completionsAt,
    expandFile,
    expandedMacro,
    extendSelection,
    findReferences,
    foldingRanges,
    highlight,
    highlightRelated,
    implementationsAt,
    macroCallAt,
    typeDefinitionAt,
    workspaceSymbols
}
import loupe.db.SourceFile
import loupe.hir.body as nativeBody
import loupe.hir.signature as nativeSignature
import loupe.hir.signatureTypes as nativeSignatureTypes
import loupe.hir.supertypes as nativeSupertypes
import loupe.hir.whenDiagnostics as nativeWhenDiagnostics
import loupe.hir.{
    Body,
    BodyMacroCall,
    DefId,
    ExprId,
    ExprScopes,
    ExtendedType,
    FieldResolution,
    InferenceResult,
    Item,
    ItemFile,
    ItemId,
    LoweredBody,
    MacroCallId,
    MemberTarget,
    Receiver,
    Signature,
    SignatureTypes,
    Ty,
    TyKind,
    TypeScope,
    WhenDiagnostics,
    bodyMacroCalls,
    bodyWithSourceMap,
    declaredTyOf,
    exprScopes,
    headTysOf,
    inferBody,
    isUnknown,
    itemOf,
    itemTreeOf,
    membersNamed,
    parentOf,
    receiverOf,
    receiverTyOf,
    resolveField,
    substitute,
    typeScopeOf
}
import loupe.vfs.{FileId, VfsPath}
@When[os == "Linux"]
import py_interop.*
@When[os == "Linux"]
import py_interop.internal_macros.DerivePython

/**
 * A revision-bound analysis handle; querying it after a workspace update reports ContentModified.
 */
@When[os == "Linux"]
@DerivePython
class AnalysisRevision {
    @PyIgnore
    AnalysisRevision(private let owner: WorkspaceState) {
        revision = owner.revision
    }

    public let revision: Int64

    private prop state: WorkspaceState {
        get() {
            if (owner.revision != revision) {
                throw IllegalStateException(
                    "ContentModified: analysis revision ${revision} is stale; acquire workspace.analysis() again"
                )
            }
            owner
        }
    }

    public func declarations(path: String): Array<DefId> {
        let file =
            state
                .db
                .sourceFile(resolve(path))
                .getOrThrow { IllegalArgumentException("file has no source analysis: ${path}") }
        let result = ArrayList<DefId>()
        collect(ItemFile.Source(file), itemTreeOf(state.db, ItemFile.Source(file)).items, result)
        result.toArray()
    }

    public func item(def: DefId): ?Item {
        itemOf(state.db, def)
    }
    public func typeScope(def: DefId): ?TypeScope {
        typeScopeOf(state.db, def)
    }
    public func whenDiagnostics(path: String): WhenDiagnostics {
        nativeWhenDiagnostics(
            state.db,
            state
                .db
                .sourceFile(resolve(path))
                .getOrThrow { IllegalArgumentException("file has no source analysis: ${path}") }
        )
    }
    public func bodyMacros(path: String): Array<BodyMacroCall> {
        bodyMacroCalls(
            state.db,
            state
                .db
                .sourceFile(resolve(path))
                .getOrThrow { IllegalArgumentException("file has no source analysis: ${path}") }
        )
    }
    public func signature(def: DefId): Signature {
        nativeSignature(state.db, def)
    }
    public func signatureTypes(def: DefId): SignatureTypes {
        nativeSignatureTypes(state.db, def)
    }
    public func body(def: DefId): Body {
        nativeBody(state.db, def)
    }
    public func loweredBody(def: DefId): LoweredBody {
        bodyWithSourceMap(state.db, def)
    }
    public func scopes(def: DefId): ExprScopes {
        exprScopes(state.db, def)
    }
    public func expandedFile(path: String, header: String): ?ExpandedFile {
        expandFile(state.db, resolve(path), header)
    }
    public func infer(def: DefId): InferenceResult {
        inferBody(state.db, def)
    }
    public func declaredType(def: DefId): Ty {
        declaredTyOf(state.db, def)
    }
    public func typeKind(ty: Ty): TyKind {
        ty.kind(state.db)
    }
    public func typeText(ty: Ty): String {
        ty.text(state.db)
    }
    public func isTypeUnknown(ty: Ty): Bool {
        isUnknown(state.db, ty)
    }
    public func internType(kind: TyKind): Ty {
        Ty(state.db, kind)
    }
    public func substituteType(ty: Ty, owner: DefId, args: Array<Ty>): Ty {
        substitute(state.db, ty, owner, args)
    }
    public func headTypes(ty: Ty): Array<Ty> {
        headTysOf(state.db, ty)
    }
    public func members(def: DefId, name: String): Array<MemberTarget> {
        membersNamed(state.db, def, name)
    }
    public func supertypes(def: DefId): Array<ExtendedType> {
        nativeSupertypes(state.db, def)
    }
    public func field(def: DefId, expr: ExprId): FieldResolution {
        resolveField(state.db, def, expr)
    }
    public func receiver(def: DefId, expr: ExprId): Receiver {
        receiverOf(state.db, def, expr)
    }
    public func receiverType(def: DefId, expr: ExprId): ?Ty {
        receiverTyOf(state.db, def, expr)
    }
    public func fileId(path: String): FileId {
        resolve(path)
    }
    public func sourceFileId(file: SourceFile): FileId {
        file.fileId(state.db)
    }
    public func text(path: String): String {
        state
            .vfs
            .fileContents(resolve(path))
            .getOrThrow { IllegalStateException("loaded file has no contents") }
            .toString()
    }
    public func parent(def: DefId): ?DefId {
        parentOf(state.db, def)
    }
    public func definitionFile(def: DefId): ItemFile {
        def.file(state.db)
    }
    public func definitionItem(def: DefId): ItemId {
        def.item(state.db)
    }
    public func path(file: FileId): String {
        state.vfs.paths.path(file).toString()
    }

    /**
     * Written ranges by expression index; None marks synthetic expressions.
     */
    public func expressionRanges(def: DefId): Array<?TextRange> {
        bodyWithSourceMap(state.db, def)
            .sourceMap
            .exprs
            .map {
                origin =>
                origin
                    .written
                    .filter { source => source.expansion.isNone() }
                    .map { source => source.ptr.range }
            }
    }

    public func localRanges(def: DefId): Array<?TextRange> {
        bodyWithSourceMap(state.db, def)
            .sourceMap
            .locals
            .map {
                origin =>
                origin
                    .written
                    .filter { source => source.expansion.isNone() }
                    .map { source => source.ptr.range }
            }
    }

    public func completions(path: String, offset: Int64): ?CompletionResult {
        completionsAt(state.db, position(path, offset), offset)
    }
    public func completionDetails(
        path: String,
        offset: Int64,
        item: CompletionItem
    ): Array<HoverItem> {
        nativeCompletionDetails(state.db, position(path, offset), offset, item)
    }
    public func references(path: String, offset: Int64): Array<AnalysisReference> {
        findReferences(state.db, position(path, offset), offset)
    }
    public func typeDefinition(path: String, offset: Int64): Array<NavigationTarget> {
        typeDefinitionAt(state.db, position(path, offset), offset)
    }
    public func implementations(path: String, offset: Int64): Array<NavigationTarget> {
        implementationsAt(state.db, position(path, offset), offset)
    }
    public func related(path: String, offset: Int64): Array<RelatedHighlight> {
        highlightRelated(state.db, position(path, offset), offset)
    }
    public func highlights(path: String): Array<HighlightedRange> {
        highlight(state.db, resolve(path))
    }
    public func folding(path: String): Array<Fold> {
        foldingRanges(state.db, resolve(path))
    }
    public func selection(path: String, offset: Int64): Array<TextRange> {
        extendSelection(state.db, position(path, offset), offset)
    }
    public func symbols(query: String, limit: Int64): Array<FoundSymbol> {
        workspaceSymbols(state.db, state.files.map { p => resolve(p.toString()) }, query, limit)
    }
    public func macroCall(path: String, offset: Int64): ?MacroCallAt {
        macroCallAt(state.db, position(path, offset), offset)
    }
    public func expansion(call: MacroCallId): ?ExpandedMacro {
        expandedMacro(state.db, call)
    }

    private func collect(file: ItemFile, items: Array<Item>, result: ArrayList<DefId>): Unit {
        for (item in items) {
            result.add(DefId(state.db, file, item.id))
            collect(file, item.members, result)
        }
    }
    private func resolve(path: String): FileId {
        let absolute =
            if (Path(path).isAbsolute()) { VfsPath.file(path) } else { state.root.join(path) }
        state.vfs.fileId(absolute) ??
            throw IllegalArgumentException("file is not loaded: ${absolute}")
    }
    private func position(path: String, offset: Int64): FileId {
        let file = resolve(path)
        let text =
            state
                .vfs
                .fileContents(file)
                .getOrThrow { IllegalStateException("loaded file has no contents") }
                .toString()
                .toArray()
        if (
            offset < 0 || offset > text.size ||
                (offset < text.size && (text[offset] & 0xC0) == 0x80)
        ) {
            throw IllegalArgumentException("offset must be a UTF-8 byte boundary within the file")
        }
        file
    }
}
