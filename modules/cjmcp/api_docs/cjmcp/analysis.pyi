class AnalysisRevision:
    """
    
    A revision-bound analysis handle; querying it after a workspace update reports ContentModified.
    
    """
    @property
    def revision(self) -> int:
        ...
    def semantic(self) -> SemanticAnalysis:
        """
        
        Snapshot views of this checked revision, cancelled by later input changes.
        @throws IllegalStateException - if this handle belongs to an older workspace revision.
        
         for type SemanticAnalysis, see 'loupe/semantic.pyi'
        """
        ...
    def declarations(self, __path: str) -> list[DefId]:
        """
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def item(self, __def: DefId) -> Item | None:
        """
         for type Item, see 'loupe.hir/item_tree.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def typeScope(self, __def: DefId) -> TypeScope | None:
        """
         for type TypeScope, see 'loupe.hir/type_path.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def whenDiagnostics(self, __path: str) -> WhenDiagnostics:
        """
         for type WhenDiagnostics, see 'loupe.hir/when.pyi'
        """
        ...
    def bodyMacros(self, __path: str) -> list[BodyMacroCall]:
        """
         for type BodyMacroCall, see 'loupe.hir/body_macro.pyi'
        """
        ...
    def signature(self, __def: DefId) -> Signature:
        """
         for type Signature, see 'loupe.hir/signature.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def signatureWithSourceMap(self, __def: DefId) -> PythonLoweredSignature:
        """
         for type PythonLoweredSignature, see 'cjmcp/python_signature.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def signatureTypes(self, __def: DefId) -> SignatureTypes:
        """
         for type SignatureTypes, see 'loupe.hir/signature_types.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def body(self, __def: DefId) -> Body:
        """
         for type Body, see 'loupe.hir/body.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def loweredBody(self, __def: DefId) -> LoweredBody:
        """
         for type LoweredBody, see 'loupe.hir/body.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def scopes(self, __def: DefId) -> ExprScopes:
        """
         for type ExprScopes, see 'loupe.hir/expr_scopes.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def expandedFile(self, __path: str, __header: str) -> ExpandedFile | None:
        """
         for type ExpandedFile, see 'loupe/expanded_file.pyi'
        """
        ...
    def trackedCallRoots(self, __path: str) -> list[DefId]:
        """
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def directCalls(self, __def: DefId) -> DirectCalls:
        """
         for type DirectCalls, see 'loupe/direct_calls.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def callDeclaration(self, __def: DefId) -> CallDeclaration:
        """
         for type CallDeclaration, see 'loupe/direct_calls.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def infer(self, __def: DefId) -> InferenceResult:
        """
         for type InferenceResult, see 'loupe.hir/infer.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def declaredType(self, __def: DefId) -> Ty:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def typeKind(self, __ty: Ty) -> TyKind:
        """
         for type TyKind, see 'loupe.hir/ty.pyi'
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    def typeText(self, __ty: Ty) -> str:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    def isTypeUnknown(self, __ty: Ty) -> bool:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    def internType(self, __kind: TyKind) -> Ty:
        """
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
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    def members(self, __def: DefId, __name: str) -> list[MemberTarget]:
        """
         for type MemberTarget, see 'loupe.hir/members.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def allMembers(self, __def: DefId) -> list[MemberTarget]:
        """
         for type MemberTarget, see 'loupe.hir/members.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def supertypes(self, __def: DefId) -> list[ExtendedType]:
        """
         for type ExtendedType, see 'loupe.hir/members.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def field(self, __def: DefId, __expr: ExprId) -> FieldResolution:
        """
         for type FieldResolution, see 'loupe.hir/field_resolution.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def receiver(self, __def: DefId, __expr: ExprId) -> Receiver:
        """
         for type Receiver, see 'loupe.hir/field_resolution.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def receiverType(self, __def: DefId, __expr: ExprId) -> Ty | None:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def fileId(self, __path: str) -> FileId:
        """
         for type FileId, see 'loupe.vfs/vfs.pyi'
        """
        ...
    def sourceFileId(self, __file: SourceFile) -> FileId:
        """
         for type FileId, see 'loupe.vfs/vfs.pyi'
         for type SourceFile, see 'loupe.db/db.pyi'
        """
        ...
    def text(self, __path: str) -> str:
        ...
    def parent(self, __def: DefId) -> DefId | None:
        """
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def definitionFile(self, __def: DefId) -> ItemFile:
        """
         for type ItemFile, see 'loupe.hir/binary.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def definitionItem(self, __def: DefId) -> ItemId:
        """
         for type ItemId, see 'loupe.hir/item_id.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def path(self, __file: FileId) -> str:
        """
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
         for type TextRange, see 'ginkgo/text_range.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def completions(self, __path: str, __offset: int) -> CompletionResult | None:
        """
         for type CompletionResult, see 'loupe/completion.pyi'
        """
        ...
    def completionDetails(self, __path: str, __offset: int, __item: CompletionItem) -> list[HoverItem]:
        """
         for type HoverItem, see 'loupe/hover.pyi'
         for type CompletionItem, see 'loupe/completion.pyi'
        """
        ...
    def references(self, __path: str, __offset: int) -> list[Reference]:
        """
         for type Reference, see 'loupe/references.pyi'
        """
        ...
    def typeDefinition(self, __path: str, __offset: int) -> list[NavigationTarget]:
        """
         for type NavigationTarget, see 'loupe/definition.pyi'
        """
        ...
    def implementations(self, __path: str, __offset: int) -> list[NavigationTarget]:
        """
         for type NavigationTarget, see 'loupe/definition.pyi'
        """
        ...
    def related(self, __path: str, __offset: int) -> list[RelatedHighlight]:
        """
         for type RelatedHighlight, see 'loupe/highlight_related.pyi'
        """
        ...
    def highlights(self, __path: str) -> list[HighlightedRange]:
        """
         for type HighlightedRange, see 'loupe/highlight.pyi'
        """
        ...
    def folding(self, __path: str) -> list[Fold]:
        """
         for type Fold, see 'loupe/folding.pyi'
        """
        ...
    def selection(self, __path: str, __offset: int) -> list[TextRange]:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    def symbols(self, __query: str, __limit: int) -> list[FoundSymbol]:
        """
         for type FoundSymbol, see 'loupe/symbols.pyi'
        """
        ...
    def fileSymbols(self, __path: str) -> list[FileSymbol]:
        """
         for type FileSymbol, see 'loupe/symbols.pyi'
        """
        ...
    def builtinTypeDoc(self, __name: str) -> BuiltinDoc | None:
        """
         for type BuiltinDoc, see 'loupe/builtin_docs.pyi'
        """
        ...
    def builtinAnnotationDoc(self, __name: str) -> BuiltinDoc | None:
        """
         for type BuiltinDoc, see 'loupe/builtin_docs.pyi'
        """
        ...
    def builtinMacroDoc(self, __name: str) -> BuiltinDoc | None:
        """
         for type BuiltinDoc, see 'loupe/builtin_docs.pyi'
        """
        ...
    def newFilePackageLine(self, __path: str) -> str | None:
        ...
    def formatting(self, __path: str) -> list[TextEdit] | None:
        """
        Explicit overloads keep the defaults available through py_interop's exact argument matching.
         for type TextEdit, see 'source_change/text_edit.pyi'
        """
        ...
    def formatting(self, __path: str, *, options: FormatOptions) -> list[TextEdit] | None:
        """
         for type TextEdit, see 'source_change/text_edit.pyi'
         for type FormatOptions, see 'cjformat/options.pyi'
        """
        ...
    def rangeFormatting(self, __path: str, __range: TextRange) -> list[TextEdit] | None:
        """
         for type TextEdit, see 'source_change/text_edit.pyi'
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    def rangeFormatting(self, __path: str, __range: TextRange, *, options: FormatOptions) -> list[TextEdit] | None:
        """
         for type TextEdit, see 'source_change/text_edit.pyi'
         for type FormatOptions, see 'cjformat/options.pyi'
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    def prepareCallHierarchy(self, __path: str, __offset: int) -> list[CallHierarchyEntry]:
        """
         for type CallHierarchyEntry, see 'loupe/call_hierarchy.pyi'
        """
        ...
    def incomingCalls(self, __entry: CallHierarchyEntry) -> list[HierarchyCalls]:
        """
         for type HierarchyCalls, see 'loupe/call_hierarchy.pyi'
         for type CallHierarchyEntry, see 'loupe/call_hierarchy.pyi'
        """
        ...
    def outgoingCalls(self, __entry: CallHierarchyEntry) -> list[HierarchyCalls]:
        """
         for type HierarchyCalls, see 'loupe/call_hierarchy.pyi'
         for type CallHierarchyEntry, see 'loupe/call_hierarchy.pyi'
        """
        ...
    def macroCall(self, __path: str, __offset: int) -> MacroCallAt | None:
        """
         for type MacroCallAt, see 'loupe/expand_macro.pyi'
        """
        ...
    def expansion(self, __call: MacroCallId) -> ExpandedMacro | None:
        """
         for type ExpandedMacro, see 'loupe/expand_macro.pyi'
         for type MacroCallId, see 'loupe.hir/expansion.pyi'
        """
        ...
    def hoverInExpansion(self, __call: MacroCallId, __offset: int) -> HoverResult | None:
        """
         for type HoverResult, see 'loupe/hover.pyi'
         for type MacroCallId, see 'loupe.hir/expansion.pyi'
        """
        ...
    def definitionInExpansion(self, __call: MacroCallId, __offset: int) -> list[NavigationTarget]:
        """
         for type NavigationTarget, see 'loupe/definition.pyi'
         for type MacroCallId, see 'loupe.hir/expansion.pyi'
        """
        ...
    def typeDefinitionInExpansion(self, __call: MacroCallId, __offset: int) -> list[NavigationTarget]:
        """
         for type NavigationTarget, see 'loupe/definition.pyi'
         for type MacroCallId, see 'loupe.hir/expansion.pyi'
        """
        ...
