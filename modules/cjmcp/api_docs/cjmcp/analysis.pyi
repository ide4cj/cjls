from typing import Literal

class AnalysisRevision:
    """
    A revision-bound analysis handle; querying it after a workspace update reports ContentModified.
    """
    @property
    def revision(self) -> int:
        ...
    def semantic(self) -> SemanticAnalysis:
        """
        Snapshot views of this checked revision, cancelled by later input changes. @throws IllegalStateException - if this handle belongs to an older workspace revision.
         for type SemanticAnalysis, see 'loupe/semantic.pyi'
        """
        ...
    def declarations(self, __path: str) -> list[DefId]:
        """
        Return declaration IDs for a loaded source path in this revision.
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def item(self, __def: DefId) -> Item | None:
        """
        Return the item-tree declaration associated with def.
         for type Item, see 'loupe.hir/item_tree.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def typeScope(self, __def: DefId) -> TypeScope | None:
        """
        Return the type-name scope of a declaration.
         for type TypeScope, see 'loupe.hir/type_path.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def whenDiagnostics(self, __path: str) -> WhenDiagnostics:
        """
        Return conditional-compilation diagnostics for a loaded path.
         for type WhenDiagnostics, see 'loupe.hir/when.pyi'
        """
        ...
    def bodyMacros(self, __path: str) -> list[BodyMacroCall]:
        """
        Return macro calls discovered inside the declaration body.
         for type BodyMacroCall, see 'loupe.hir/body_macro.pyi'
        """
        ...
    def signature(self, __def: DefId) -> Signature:
        """
        Return the lowered written signature of a declaration.
         for type Signature, see 'loupe.hir/signature.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def signatureWithSourceMap(self, __def: DefId) -> LoweredSignature:
        """
        Return the written signature together with its source mapping.
         for type LoweredSignature, see 'cjmcp/python_signature.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def signatureTypes(self, __def: DefId) -> SignatureTypes:
        """
        Return resolved signature types, generic bounds and signature type errors.
         for type SignatureTypes, see 'loupe.hir/signature_types.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def body(self, __def: DefId) -> Body:
        """
        Return the lowered body of a declaration.
         for type Body, see 'loupe.hir/body.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def loweredBody(self, __def: DefId) -> LoweredBody:
        """
        Return the lowered body with mappings between HIR IDs and source syntax.
         for type LoweredBody, see 'loupe.hir/body.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def scopes(self, __def: DefId) -> ExprScopes:
        """
        Return lexical scopes and body expression/type scope mappings.
         for type ExprScopes, see 'loupe.hir/expr_scopes.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def expandedFile(self, __path: str, __header: str) -> ExpandedFile | None:
        """
        Build displayed expanded text with the supplied header and source-origin mappings.
         for type ExpandedFile, see 'loupe/expanded_file.pyi'
        """
        ...
    def trackedCallRoots(self, __path: str) -> list[DefId]:
        """
        Return declarations eligible as roots for immediate tracked call evidence in path.
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def directCalls(self, __def: DefId) -> DirectCalls:
        """
        Return immediate call evidence and explicit gaps for a declaration; this is not a transitive call graph.
         for type DirectCalls, see 'loupe/direct_calls.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def callDeclaration(self, __def: DefId) -> CallDeclaration:
        """
        Return declaration metadata for a call-evidence target.
         for type CallDeclaration, see 'loupe/direct_calls.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def infer(self, __def: DefId) -> InferenceResult:
        """
        Return body inference results, including types, resolutions and diagnostics.
         for type InferenceResult, see 'loupe.hir/infer.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def declaredType(self, __def: DefId) -> Ty:
        """
        Return the declared type associated with a declaration.
         for type Ty, see 'loupe.hir/ty.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def typeKind(self, __ty: Ty) -> TyKind:
        """
        Inspect the native TyKind of a type from this revision.
         for type TyKind, see 'loupe.hir/ty.pyi'
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    def typeText(self, __ty: Ty) -> str:
        """
        Format a type from this revision for display.
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    def isTypeUnknown(self, __ty: Ty) -> bool:
        """
        Whether the type represents an unknown analysis result.
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    def internType(self, __kind: TyKind) -> Ty:
        """
        Intern a native TyKind in this revision and return its Ty handle.
         for type Ty, see 'loupe.hir/ty.pyi'
         for type TyKind, see 'loupe.hir/ty.pyi'
        """
        ...
    def substituteType(self, __ty: Ty, __owner: DefId, __args: list[Ty]) -> Ty:
        """
         for type DefId, see 'loupe.hir/def_map.pyi'
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    def headTypes(self, __ty: Ty) -> list[Ty]:
        """
        Return the head types considered by native type lookup.
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    def members(self, __def: DefId, __name: str) -> list[MemberTarget]:
        """
        Return member targets named name on the declaration.
         for type MemberTarget, see 'loupe.hir/members.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def allMembers(self, __def: DefId) -> list[MemberTarget]:
        """
        Return all member targets considered by native member lookup.
         for type MemberTarget, see 'loupe.hir/members.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def supertypes(self, __def: DefId) -> list[ExtendedType]:
        """
        Return the declaration supertypes as native ExtendedType values.
         for type ExtendedType, see 'loupe.hir/members.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def field(self, __def: DefId, __expr: ExprId) -> FieldResolution:
        """
        Resolve a field-access expression in the declaration body.
         for type FieldResolution, see 'loupe.hir/field_resolution.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def receiver(self, __def: DefId, __expr: ExprId) -> Receiver:
        """
        Return native receiver evidence for a body expression.
         for type Receiver, see 'loupe.hir/field_resolution.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def receiverType(self, __def: DefId, __expr: ExprId) -> Ty | None:
        """
        Return the type of a resolved receiver, or None when unavailable.
         for type Ty, see 'loupe.hir/ty.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def fileId(self, __path: str) -> FileId:
        """
        Resolve a loaded path to its native FileId; relative paths use the selected root.
         for type FileId, see 'loupe.vfs/vfs.pyi'
        """
        ...
    def sourceFileId(self, __file: SourceFile) -> FileId:
        """
        Return the physical FileId associated with a contextual SourceFile.
         for type FileId, see 'loupe.vfs/vfs.pyi'
         for type SourceFile, see 'loupe.db/db.pyi'
        """
        ...
    def text(self, __path: str) -> str:
        """
        Return text from this revision. Raises RuntimeError if a loaded file has no text.
        """
        ...
    def parent(self, __def: DefId) -> DefId | None:
        """
        Return the enclosing declaration, or None for a top-level declaration.
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def definitionFile(self, __def: DefId) -> ItemFile:
        """
        Return the source, binary or expansion ItemFile containing def.
         for type ItemFile, see 'loupe.hir/binary.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def definitionItem(self, __def: DefId) -> ItemId:
        """
        Return the item-tree ID associated with def.
         for type ItemId, see 'loupe.hir/item_id.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def path(self, __file: FileId) -> str:
        """
        Return the path associated with a physical FileId.
         for type FileId, see 'loupe.vfs/vfs.pyi'
        """
        ...
    def expressionRanges(self, __def: DefId) -> list[TextRange | None]:
        """
        Written ranges by expression index; None marks synthetic expressions.
         for type TextRange, see 'ginkgo/text_range.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def localRanges(self, __def: DefId) -> list[TextRange | None]:
        """
        Optional written declaration ranges indexed by LocalId; None for bindings without a written non-expansion source.
         for type TextRange, see 'ginkgo/text_range.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def completions(self, __path: str, __offset: int) -> CompletionResult | None:
        """
        Return completion candidates at a UTF-8 byte offset in a loaded path.
         for type CompletionResult, see 'loupe/completion.pyi'
        """
        ...
    def completionDetails(self, __path: str, __offset: int, __item: CompletionItem) -> list[HoverItem]:
        """
        Resolve deferred completion details for a completion candidate.
         for type HoverItem, see 'loupe/hover.pyi'
         for type CompletionItem, see 'loupe/completion.pyi'
        """
        ...
    def references(self, __path: str, __offset: int) -> list[Reference]:
        """
        Return reference sites at a UTF-8 byte offset, retaining each site's declaration marker.
         for type Reference, see 'loupe/references.pyi'
        """
        ...
    def typeDefinition(self, __path: str, __offset: int) -> list[NavigationTarget]:
        """
        Return type-definition targets at a UTF-8 byte offset.
         for type NavigationTarget, see 'loupe/definition.pyi'
        """
        ...
    def implementations(self, __path: str, __offset: int) -> list[NavigationTarget]:
        """
        Return implementation targets at a UTF-8 byte offset.
         for type NavigationTarget, see 'loupe/definition.pyi'
        """
        ...
    def related(self, __path: str, __offset: int) -> list[RelatedHighlight]:
        """
        Return related-symbol highlights at a UTF-8 byte offset.
         for type RelatedHighlight, see 'loupe/highlight_related.pyi'
        """
        ...
    def highlights(self, __path: str) -> list[HighlightedRange]:
        """
        Return semantic highlighting ranges for a loaded path.
         for type HighlightedRange, see 'loupe/highlight.pyi'
        """
        ...
    def folding(self, __path: str) -> list[Fold]:
        """
        Return foldable source ranges for a loaded path.
         for type Fold, see 'loupe/folding.pyi'
        """
        ...
    def selection(self, __path: str, __offset: int) -> list[TextRange]:
        """
        Return enclosing selection ranges at a UTF-8 byte offset.
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    def symbols(self, __query: str, __limit: int) -> list[FoundSymbol]:
        """
        Search workspace symbols by query, returning at most limit matches; a full limit may omit matches.
         for type FoundSymbol, see 'loupe/symbols.pyi'
        """
        ...
    def fileSymbols(self, __path: str) -> list[FileSymbol]:
        """
        Return declaration symbols and their UTF-8 source ranges for a loaded path.
         for type FileSymbol, see 'loupe/symbols.pyi'
        """
        ...
    def builtinTypeDoc(self, __name: str) -> BuiltinDoc | None:
        """
        Return documentation for a built-in type name, or None when unknown.
         for type BuiltinDoc, see 'loupe/builtin_docs.pyi'
        """
        ...
    def builtinAnnotationDoc(self, __name: str) -> BuiltinDoc | None:
        """
        Return documentation for a built-in annotation name, or None when unknown.
         for type BuiltinDoc, see 'loupe/builtin_docs.pyi'
        """
        ...
    def builtinMacroDoc(self, __name: str) -> BuiltinDoc | None:
        """
        Return documentation for a built-in macro name, or None when unknown.
         for type BuiltinDoc, see 'loupe/builtin_docs.pyi'
        """
        ...
    def newFilePackageLine(self, __path: str) -> str | None:
        """
        Return the package header for a new path, or None outside loaded packages.
        """
        ...
    def formatting(self, __path: str) -> list[TextEdit] | None:
        """
        Return UTF-8 TextEdits without applying them; None means syntax errors, [] means already formatted. Options default to library defaults.
         for type TextEdit, see 'source_change/text_edit.pyi'
        """
        ...
    def formatting(self, __path: str, *, options: FormatOptions) -> list[TextEdit] | None:
        """
        Return UTF-8 TextEdits without applying them; None means syntax errors, [] means already formatted. Options default to library defaults.
         for type TextEdit, see 'source_change/text_edit.pyi'
         for type FormatOptions, see 'cjformat/options.pyi'
        """
        ...
    def rangeFormatting(self, __path: str, __range: TextRange) -> list[TextEdit] | None:
        """
        Return formatting edits for the enclosing syntax node of a UTF-8 range. None means syntax errors. Options default to library defaults.
         for type TextEdit, see 'source_change/text_edit.pyi'
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    def rangeFormatting(self, __path: str, __range: TextRange, *, options: FormatOptions) -> list[TextEdit] | None:
        """
        Return formatting edits for the enclosing syntax node of a UTF-8 range. None means syntax errors. Options default to library defaults.
         for type TextEdit, see 'source_change/text_edit.pyi'
         for type FormatOptions, see 'cjformat/options.pyi'
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    def prepareCallHierarchy(self, __path: str, __offset: int) -> list[CallHierarchyEntry]:
        """
        Return callable hierarchy entries at a UTF-8 byte offset.
         for type CallHierarchyEntry, see 'loupe/call_hierarchy.pyi'
        """
        ...
    def incomingCalls(self, __entry: CallHierarchyEntry) -> list[HierarchyCalls]:
        """
        Return direct caller groups and their call-site ranges.
         for type HierarchyCalls, see 'loupe/call_hierarchy.pyi'
         for type CallHierarchyEntry, see 'loupe/call_hierarchy.pyi'
        """
        ...
    def outgoingCalls(self, __entry: CallHierarchyEntry) -> list[HierarchyCalls]:
        """
        Return direct callee groups and their call-site ranges.
         for type HierarchyCalls, see 'loupe/call_hierarchy.pyi'
         for type CallHierarchyEntry, see 'loupe/call_hierarchy.pyi'
        """
        ...
    def macroCall(self, __path: str, __offset: int) -> MacroCallAt | None:
        """
        Find the macro call at a UTF-8 byte offset, or None when absent.
         for type MacroCallAt, see 'loupe/expand_macro.pyi'
        """
        ...
    def expansion(self, __call: MacroCallId) -> ExpandedMacro | None:
        """
        Return a macro expansion and its source mapping when available.
         for type ExpandedMacro, see 'loupe/expand_macro.pyi'
         for type MacroCallId, see 'loupe.hir/expansion.pyi'
        """
        ...
    def hoverInExpansion(self, __call: MacroCallId, __offset: int) -> HoverResult | None:
        """
        Return hover information at a UTF-8 offset in expansion text.
         for type HoverResult, see 'loupe/hover.pyi'
         for type MacroCallId, see 'loupe.hir/expansion.pyi'
        """
        ...
    def definitionInExpansion(self, __call: MacroCallId, __offset: int) -> list[NavigationTarget]:
        """
        Return definition targets at a UTF-8 offset in expansion text.
         for type NavigationTarget, see 'loupe/definition.pyi'
         for type MacroCallId, see 'loupe.hir/expansion.pyi'
        """
        ...
    def typeDefinitionInExpansion(self, __call: MacroCallId, __offset: int) -> list[NavigationTarget]:
        """
        Return type-definition targets at a UTF-8 offset in expansion text.
         for type NavigationTarget, see 'loupe/definition.pyi'
         for type MacroCallId, see 'loupe.hir/expansion.pyi'
        """
        ...
