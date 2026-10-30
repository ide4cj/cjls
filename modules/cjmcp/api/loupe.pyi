"""Handwritten reference for globals injected into cjmcp runPython scripts.

Read this file; do not import it. There is no importable `loupe` Python package.
Workspace and AnalysisRevision methods and all exported HIR enum variants are
covered; other result types are partial.
_Partial marks types whose remaining fields/variants are not documented yet.
Native immutable fields are properties, arrays become lists, and options become
None. Constructors are listed only where needed by the accompanying recipes.
"""

from typing import Any, ClassVar, overload


class _Partial:
    """Reference-only helper: omitted members have not been described yet."""
    def __getattr__(self, name: str) -> Any: ...


class Workspace:
    """Use the injected workspace instance; paths may be relative to its root."""
    @property
    def root(self) -> str: ...
    @property
    def revision(self) -> int:
        """Session-local revision fixed for this script and returned in the tool response."""
        ...
    @property
    def problems(self) -> list[str]:
        """Loading, macro build and expansion problems; check before interpreting results."""
        ...
    @property
    def hasExpandedMacros(self) -> bool: ...
    def files(self) -> list[str]: ...
    def reload(self) -> None:
        """Request preparation after this script; current analysis remains fixed."""
        ...
    def analysis(self) -> AnalysisRevision:
        """Capture the loaded revision, including its text, identities and caches."""
        ...
    def structure(self, path: str) -> list[StructureNode]: ...
    def diagnostics(self, path: str) -> list[Diagnostic]: ...
    def hover(self, path: str, offset: int) -> HoverResult | None: ...
    def definition(self, path: str, offset: int) -> list[Location]: ...


workspace: Workspace


class AnalysisRevision:
    """Obtain from workspace.analysis(); fixed throughout the current script.

After a workspace update, queries raise RuntimeError containing ContentModified.
Reacquire the analysis handle and recompute its DefId, Ty, FileId and other
identities; never mix revisions. Offsets are zero-based UTF-8 bytes on character
boundaries; range ends are exclusive. Unloaded paths and invalid positions raise
RuntimeError via the native callback. Queries read revision text, not live disk.
"""
    @property
    def revision(self) -> int:
        """Workspace revision in which this handle was captured."""
        ...
    def declarations(self, path: str) -> list[DefId]:
        """Declarations including nested members, in source order."""
        ...
    def item(self, definition: DefId, /) -> Item | None: ...
    def parent(self, definition: DefId, /) -> DefId | None: ...
    def definitionFile(self, definition: DefId, /) -> ItemFile: ...
    def definitionItem(self, definition: DefId, /) -> ItemId: ...
    def fileId(self, path: str) -> FileId: ...
    def sourceFileId(self, file: SourceFile) -> FileId: ...
    def path(self, file: FileId) -> str: ...
    def text(self, path: str) -> str: ...
    def signature(self, definition: DefId, /) -> Signature: ...
    def signatureTypes(self, definition: DefId, /) -> SignatureTypes: ...
    def typeScope(self, definition: DefId, /) -> TypeScope | None: ...
    def body(self, definition: DefId, /) -> Body: ...
    def loweredBody(self, definition: DefId, /) -> LoweredBody: ...
    def scopes(self, definition: DefId, /) -> ExprScopes: ...
    def infer(self, definition: DefId, /) -> InferenceResult: ...
    def expressionRanges(self, definition: DefId, /) -> list[TextRange | None]:
        """By body expression index; None for synthetic or expansion-relative origins."""
        ...
    def localRanges(self, definition: DefId, /) -> list[TextRange | None]:
        """By body local index; non-null ranges always belong to the source file."""
        ...
    def declaredType(self, definition: DefId, /) -> Ty: ...
    def typeKind(self, ty: Ty) -> TyKind: ...
    def typeText(self, ty: Ty) -> str:
        """Display text; ErrorTy, TodoTy and UnknownTy all display as {unknown}."""
        ...
    def isTypeUnknown(self, ty: Ty) -> bool: ...
    def internType(self, kind: TyKind) -> Ty: ...
    def substituteType(self, ty: Ty, owner: DefId, args: list[Ty]) -> Ty: ...
    def headTypes(self, ty: Ty) -> list[Ty]: ...
    def members(self, definition: DefId, name: str, /) -> list[MemberTarget]: ...
    def supertypes(self, definition: DefId, /) -> list[ExtendedType]: ...
    def field(self, definition: DefId, expr: ExprId, /) -> FieldResolution: ...
    def receiver(self, definition: DefId, expr: ExprId, /) -> Receiver: ...
    def receiverType(self, definition: DefId, expr: ExprId, /) -> Ty | None: ...
    def completions(self, path: str, offset: int) -> CompletionResult | None: ...
    def completionDetails(self, path: str, offset: int, item: CompletionItem) -> list[HoverItem]: ...
    def references(self, path: str, offset: int) -> list[Reference]: ...
    def typeDefinition(self, path: str, offset: int) -> list[NavigationTarget]: ...
    def implementations(self, path: str, offset: int) -> list[NavigationTarget]: ...
    def related(self, path: str, offset: int) -> list[RelatedHighlight]: ...
    def highlights(self, path: str) -> list[HighlightedRange]: ...
    def folding(self, path: str) -> list[Fold]: ...
    def selection(self, path: str, offset: int) -> list[TextRange]: ...
    def symbols(self, query: str, limit: int) -> list[FoundSymbol]:
        """Case-insensitive subsequence name search, at most limit declarations."""
        ...
    def whenDiagnostics(self, path: str) -> WhenDiagnostics: ...
    def bodyMacros(self, path: str) -> list[BodyMacroCall]: ...
    def macroCall(self, path: str, offset: int) -> MacroCallAt | None: ...
    def expansion(self, call: MacroCallId) -> ExpandedMacro | None: ...
    def expandedFile(self, path: str, header: str) -> ExpandedFile | None: ...


class TextRange(_Partial):
    """UTF-8 byte interval [start, end), never Python string indices."""
    def __init__(self, start: int, end: int) -> None: ...
    @property
    def start(self) -> int: ...
    @property
    def end(self) -> int: ...
    @property
    def len(self) -> int:
        """Read-only UTF-8 byte length, end - start; use range.len without parentheses."""
        ...
    def isEmpty(self) -> bool: ...


class StructureKind(_Partial):
    """Native enum; compare to StructureKind.Function(), or call toString()."""
    def toString(self) -> str: ...


class StructureNode:
    @property
    def name(self) -> str: ...
    @property
    def kind(self) -> StructureKind: ...
    @property
    def range(self) -> TextRange: ...
    @property
    def selectionRange(self) -> TextRange: ...
    @property
    def children(self) -> list[StructureNode]: ...


class Severity(_Partial):
    """Native variants Error(), Warning(), Hint(); not Python enum constants."""


class Diagnostic:
    @property
    def range(self) -> TextRange: ...
    @property
    def severity(self) -> Severity: ...
    @property
    def message(self) -> str: ...
    @property
    def unnecessary(self) -> bool: ...


class HoverItem:
    @property
    def code(self) -> str: ...
    @property
    def path(self) -> str | None: ...
    @property
    def doc(self) -> str | None: ...


class HoverResult:
    @property
    def range(self) -> TextRange: ...
    @property
    def items(self) -> list[HoverItem]: ...


class Location:
    """Workspace.definition result; selectionRange is the name, range the full node."""
    @property
    def path(self) -> str: ...
    @property
    def range(self) -> TextRange: ...
    @property
    def selectionRange(self) -> TextRange: ...


class NavigationTarget:
    @property
    def fileId(self) -> FileId: ...
    @property
    def fullRange(self) -> TextRange: ...
    @property
    def focusRange(self) -> TextRange: ...
    @property
    def expansion(self) -> MacroCallId | None:
        """If present, ranges refer to this expansion's text, not fileId's source text."""
        ...


class ReferenceAccess(_Partial):
    """ReadAccess()/WriteAccess(); toString() returns 'read'/'write'."""
    def toString(self) -> str: ...


class Reference:
    @property
    def fileId(self) -> FileId: ...
    @property
    def range(self) -> TextRange: ...
    @property
    def access(self) -> ReferenceAccess | None: ...
    @property
    def isDeclaration(self) -> bool: ...


class RelatedHighlight:
    @property
    def range(self) -> TextRange: ...
    @property
    def access(self) -> ReferenceAccess | None: ...


class FileSymbol:
    @property
    def name(self) -> str: ...
    @property
    def kind(self) -> StructureKind: ...
    @property
    def range(self) -> TextRange: ...
    @property
    def selectionRange(self) -> TextRange: ...
    @property
    def containerName(self) -> str | None: ...


class FoundSymbol:
    @property
    def fileId(self) -> FileId: ...
    @property
    def symbol(self) -> FileSymbol: ...


class CompletionItem:
    @property
    def label(self) -> str: ...
    @property
    def kind(self) -> CompletionKind: ...
    @property
    def relevance(self) -> int: ...
    @property
    def source(self) -> CompletionSource: ...
    @property
    def overloadCount(self) -> int: ...


class CompletionResult:
    @property
    def range(self) -> TextRange: ...
    @property
    def items(self) -> list[CompletionItem]: ...


class Fold:
    @property
    def range(self) -> TextRange: ...
    @property
    def kind(self) -> FoldKind: ...


class HighlightedRange:
    @property
    def range(self) -> TextRange: ...
    @property
    def tag(self) -> HighlightTag: ...
    @property
    def modifiers(self) -> HighlightModifiers: ...


# Opaque database identities: query through the producing AnalysisRevision.
# They support native equality/hashing, but have no public Python constructors.
class DefId: ...
class Ty: ...
class MacroCallId: ...
class SourceFile: ...


class FileId:
    """VFS index; resolve real files through analysis.fileId(path)."""
    def __init__(self, index: int) -> None: ...
    @property
    def index(self) -> int: ...


class ExprId:
    def __init__(self, index: int) -> None: ...
    @property
    def index(self) -> int: ...


class PatId:
    def __init__(self, index: int) -> None: ...
    @property
    def index(self) -> int: ...


class LocalId:
    def __init__(self, index: int) -> None: ...
    @property
    def index(self) -> int: ...


class TypeRefId:
    def __init__(self, index: int) -> None: ...
    @property
    def index(self) -> int: ...


class Item(_Partial):
    @property
    def id(self) -> ItemId: ...
    @property
    def names(self) -> list[str]: ...
    @property
    def kind(self) -> ItemKind: ...
    @property
    def members(self) -> list[Item]: ...
    @property
    def macros(self) -> list[str]: ...


class Signature(_Partial):
    @property
    def generics(self) -> list[str]: ...
    @property
    def types(self) -> list[TypeRef]: ...
    @property
    def params(self) -> list[TypeRefId]: ...
    @property
    def paramNames(self) -> list[str | None]: ...
    @property
    def ty(self) -> TypeRefId | None: ...
    def text(self, id: TypeRefId) -> str: ...
    @property
    def paramDefaults(self) -> list[bool]: ...
    @property
    def isCVariadic(self) -> bool: ...
    @property
    def supers(self) -> list[TypeRefId]: ...
    @property
    def bounds(self) -> list[TypeBound]: ...


class SignatureTypes(_Partial):
    @property
    def generics(self) -> list[str]: ...
    @property
    def params(self) -> list[Ty]: ...
    @property
    def paramNames(self) -> list[str | None]: ...
    @property
    def ty(self) -> Ty | None: ...
    @property
    def paramDefaults(self) -> list[bool]: ...
    @property
    def isCVariadic(self) -> bool: ...
    @property
    def supers(self) -> list[Ty]: ...
    @property
    def bounds(self) -> list[TyBound]: ...
    @property
    def errors(self) -> list[TyError]: ...
    @property
    def typePaths(self) -> list[TypePathTarget]: ...


class Local(_Partial):
    @property
    def name(self) -> str: ...
    @property
    def kind(self) -> LocalKind: ...
    @property
    def lone(self) -> bool: ...


class Body(_Partial):
    """Arrays share indices with InferenceResult and BodySourceMap."""
    @property
    def exprs(self) -> list[Expr]: ...
    @property
    def pats(self) -> list[Pat]: ...
    @property
    def locals(self) -> list[Local]: ...
    @property
    def types(self) -> list[TypeRef]: ...
    @property
    def value(self) -> ExprId | None: ...
    @overload
    def __getitem__(self, id: ExprId) -> Expr: ...
    @overload
    def __getitem__(self, id: PatId) -> Pat: ...
    @overload
    def __getitem__(self, id: LocalId) -> Local: ...
    def typesAsSignature(self) -> Signature: ...
    @property
    def funcs(self) -> list[LocalFunc]: ...
    @property
    def params(self) -> list[BodyParam]: ...
    @property
    def accessors(self) -> list[ExprId]: ...
    @property
    def attrs(self) -> list[DeclAttr]: ...


class InferenceResult(_Partial):
    @property
    def exprs(self) -> list[Ty | None]:
        """None means no value (e.g. a package before a dot), not an unknown type."""
        ...
    @property
    def pats(self) -> list[Ty]: ...
    @property
    def locals(self) -> list[Ty]: ...
    @property
    def ty(self) -> Ty | None: ...
    @property
    def diagnostics(self) -> list[InferenceDiagnostic]: ...
    @property
    def callees(self) -> list[CalleeTarget]: ...
    def __getitem__(self, id: ExprId | PatId | LocalId) -> Ty | None: ...
    def calleeOf(self, expr: ExprId) -> DefId | None:
        """Takes the callee expression's id, not necessarily the CallExpr's id."""
        ...
    def initializerOf(self, expr: ExprId) -> DefId | None: ...
    def calleesOf(self, expr: ExprId) -> list[DefId]: ...
    def fieldOf(self, expr: ExprId) -> list[MemberTarget] | None: ...
    def paramsOf(self, expr: ExprId) -> list[int] | None: ...
    def nameOf(self, expr: ExprId) -> BodyResolution | None: ...
    def accessOf(self, expr: ExprId) -> FieldResolution | None: ...
    def typePathOf(self, ty: TypeRefId) -> list[PathResolution] | None: ...


class CalleeTarget:
    @property
    def expr(self) -> ExprId: ...
    @property
    def decl(self) -> DefId: ...
    @property
    def isInitializer(self) -> bool: ...
    def keyIndex(self) -> int: ...


class LoweredBody:
    @property
    def body(self) -> Body: ...
    @property
    def sourceMap(self) -> BodySourceMap: ...


class BodySourceMap(_Partial):
    @property
    def exprs(self) -> list[BodyOrigin]: ...
    @property
    def pats(self) -> list[BodyOrigin]: ...
    @property
    def locals(self) -> list[BodyOrigin]: ...
    @property
    def types(self) -> list[BodyOrigin]: ...
    def exprAtSource(self, source: BodySource) -> ExprId | None: ...


class BodySource:
    @property
    def range(self) -> TextRange: ...
    @property
    def kind(self) -> str: ...
    @property
    def expansion(self) -> MacroCallId | None: ...


class MacroCallAt:
    @property
    def call(self) -> MacroCallId: ...
    @property
    def range(self) -> TextRange: ...
    @property
    def focus(self) -> TextRange | None: ...


class ExpandedMacro:
    @property
    def name(self) -> str: ...
    @property
    def range(self) -> TextRange: ...
    @property
    def text(self) -> str: ...
    @property
    def kind(self) -> ExpansionKind: ...
    @property
    def declaration(self) -> str | None: ...


# Remaining result types are named for discovery, with details deferred.
# See src/python_types.cj for all registered globals, including types not listed here.
class ItemId(_Partial): ...
class TypeScope(_Partial): ...
class ExprScopes(_Partial): ...
class CompletionKind(_Partial): ...
class CompletionSource(_Partial): ...
class HighlightTag(_Partial): ...
class HighlightModifiers(_Partial): ...
class FoldKind(_Partial): ...
class WhenDiagnostics(_Partial): ...
class BodyMacroCall(_Partial): ...
class ExpandedFile(_Partial): ...
class ExpansionKind(_Partial): ...


# HIR enum variants. Private helper names describe native nested classes;
# only the public enum names are injected into scripts.
# _Partial on enum bases covers additional native methods, not omitted variants.


class ItemFile(_Partial):
    @property
    def kind(self) -> str: ...
    Source: ClassVar[type[_ItemFileSource]]
    Binary: ClassVar[type[_ItemFileBinary]]
    Expansion: ClassVar[type[_ItemFileExpansion]]
    CompilerBuiltIns: ClassVar[type[_ItemFileCompilerBuiltIns]]


class _ItemFileSource(ItemFile):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: SourceFile) -> None: ...
    @property
    def field0(self) -> SourceFile: ...


class _ItemFileBinary(ItemFile):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: BinaryPackageFile, field1: int) -> None: ...
    @property
    def field0(self) -> BinaryPackageFile: ...
    @property
    def field1(self) -> int: ...


class _ItemFileExpansion(ItemFile):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: MacroCallId) -> None: ...
    @property
    def field0(self) -> MacroCallId: ...


class _ItemFileCompilerBuiltIns(ItemFile):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: Package) -> None: ...
    @property
    def field0(self) -> Package: ...


class LocalKind(_Partial):
    @property
    def kind(self) -> str: ...
    ParamLocal: ClassVar[type[_LocalKindParamLocal]]
    LambdaParamLocal: ClassVar[type[_LocalKindLambdaParamLocal]]
    VarLocal: ClassVar[type[_LocalKindVarLocal]]
    FuncLocal: ClassVar[type[_LocalKindFuncLocal]]
    PatLocal: ClassVar[type[_LocalKindPatLocal]]
    CatchLocal: ClassVar[type[_LocalKindCatchLocal]]
    ResourceLocal: ClassVar[type[_LocalKindResourceLocal]]


class _LocalKindParamLocal(LocalKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LocalKindLambdaParamLocal(LocalKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LocalKindVarLocal(LocalKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LocalKindFuncLocal(LocalKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LocalKindPatLocal(LocalKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LocalKindCatchLocal(LocalKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LocalKindResourceLocal(LocalKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class Stmt(_Partial):
    @property
    def kind(self) -> str: ...
    LetStmt: ClassVar[type[_StmtLetStmt]]
    ExprStmt: ClassVar[type[_StmtExprStmt]]
    FuncStmt: ClassVar[type[_StmtFuncStmt]]


class _StmtLetStmt(Stmt):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2')
    def __init__(self, field0: PatId, field1: TypeRefId | None, field2: ExprId | None) -> None: ...
    @property
    def field0(self) -> PatId: ...
    @property
    def field1(self) -> TypeRefId | None: ...
    @property
    def field2(self) -> ExprId | None: ...


class _StmtExprStmt(Stmt):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: ExprId) -> None: ...
    @property
    def field0(self) -> ExprId: ...


class _StmtFuncStmt(Stmt):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: int) -> None: ...
    @property
    def field0(self) -> int: ...


class Expr(_Partial):
    @property
    def kind(self) -> str: ...
    MissingExpr: ClassVar[type[_ExprMissingExpr]]
    LitExpr: ClassVar[type[_ExprLitExpr]]
    StrExpr: ClassVar[type[_ExprStrExpr]]
    PathExpr: ClassVar[type[_ExprPathExpr]]
    FieldExpr: ClassVar[type[_ExprFieldExpr]]
    CallExpr: ClassVar[type[_ExprCallExpr]]
    IndexExpr: ClassVar[type[_ExprIndexExpr]]
    UnaryExpr: ClassVar[type[_ExprUnaryExpr]]
    BinaryExpr: ClassVar[type[_ExprBinaryExpr]]
    IsExpr: ClassVar[type[_ExprIsExpr]]
    AsExpr: ClassVar[type[_ExprAsExpr]]
    RangeExpr: ClassVar[type[_ExprRangeExpr]]
    PostfixExpr: ClassVar[type[_ExprPostfixExpr]]
    AssignedExpr: ClassVar[type[_ExprAssignedExpr]]
    TupleExpr: ClassVar[type[_ExprTupleExpr]]
    ArrayExpr: ClassVar[type[_ExprArrayExpr]]
    UnitExpr: ClassVar[type[_ExprUnitExpr]]
    IfExpr: ClassVar[type[_ExprIfExpr]]
    LetExpr: ClassVar[type[_ExprLetExpr]]
    MatchExpr: ClassVar[type[_ExprMatchExpr]]
    QuestMatchExpr: ClassVar[type[_ExprQuestMatchExpr]]
    TryExpr: ClassVar[type[_ExprTryExpr]]
    ForExpr: ClassVar[type[_ExprForExpr]]
    WhileExpr: ClassVar[type[_ExprWhileExpr]]
    DoWhileExpr: ClassVar[type[_ExprDoWhileExpr]]
    ThrowExpr: ClassVar[type[_ExprThrowExpr]]
    ReturnExpr: ClassVar[type[_ExprReturnExpr]]
    BreakExpr: ClassVar[type[_ExprBreakExpr]]
    ContinueExpr: ClassVar[type[_ExprContinueExpr]]
    SpawnExpr: ClassVar[type[_ExprSpawnExpr]]
    SynchronizedExpr: ClassVar[type[_ExprSynchronizedExpr]]
    UnsafeExpr: ClassVar[type[_ExprUnsafeExpr]]
    LambdaExpr: ClassVar[type[_ExprLambdaExpr]]
    ThisExpr: ClassVar[type[_ExprThisExpr]]
    SuperExpr: ClassVar[type[_ExprSuperExpr]]
    WildcardExpr: ClassVar[type[_ExprWildcardExpr]]
    ConvExpr: ClassVar[type[_ExprConvExpr]]
    PrimExpr: ClassVar[type[_ExprPrimExpr]]
    TypeExpr: ClassVar[type[_ExprTypeExpr]]
    LangExpr: ClassVar[type[_ExprLangExpr]]
    BlockExpr: ClassVar[type[_ExprBlockExpr]]
    QuoteExpr: ClassVar[type[_ExprQuoteExpr]]
    MacroExpr: ClassVar[type[_ExprMacroExpr]]


class _ExprMissingExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ExprLitExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: str) -> None: ...
    @property
    def field0(self) -> str: ...


class _ExprStrExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[ExprId]) -> None: ...
    @property
    def field0(self) -> list[ExprId]: ...


class _ExprPathExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: str, field1: list[TypeRefId]) -> None: ...
    @property
    def field0(self) -> str: ...
    @property
    def field1(self) -> list[TypeRefId]: ...


class _ExprFieldExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2')
    def __init__(self, field0: ExprId, field1: str, field2: list[TypeRefId]) -> None: ...
    @property
    def field0(self) -> ExprId: ...
    @property
    def field1(self) -> str: ...
    @property
    def field2(self) -> list[TypeRefId]: ...


class _ExprCallExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: ExprId, field1: list[CallArg]) -> None: ...
    @property
    def field0(self) -> ExprId: ...
    @property
    def field1(self) -> list[CallArg]: ...


class _ExprIndexExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: ExprId, field1: list[ExprId]) -> None: ...
    @property
    def field0(self) -> ExprId: ...
    @property
    def field1(self) -> list[ExprId]: ...


class _ExprUnaryExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: str, field1: ExprId) -> None: ...
    @property
    def field0(self) -> str: ...
    @property
    def field1(self) -> ExprId: ...


class _ExprBinaryExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2')
    def __init__(self, field0: str, field1: ExprId, field2: ExprId) -> None: ...
    @property
    def field0(self) -> str: ...
    @property
    def field1(self) -> ExprId: ...
    @property
    def field2(self) -> ExprId: ...


class _ExprIsExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: ExprId, field1: TypeRefId) -> None: ...
    @property
    def field0(self) -> ExprId: ...
    @property
    def field1(self) -> TypeRefId: ...


class _ExprAsExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: ExprId, field1: TypeRefId) -> None: ...
    @property
    def field0(self) -> ExprId: ...
    @property
    def field1(self) -> TypeRefId: ...


class _ExprRangeExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2', 'field3')
    def __init__(self, field0: ExprId | None, field1: ExprId | None, field2: ExprId | None, field3: bool) -> None: ...
    @property
    def field0(self) -> ExprId | None: ...
    @property
    def field1(self) -> ExprId | None: ...
    @property
    def field2(self) -> ExprId | None: ...
    @property
    def field3(self) -> bool: ...


class _ExprPostfixExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2')
    def __init__(self, field0: ExprId, field1: str, field2: ExprId | None) -> None: ...
    @property
    def field0(self) -> ExprId: ...
    @property
    def field1(self) -> str: ...
    @property
    def field2(self) -> ExprId | None: ...


class _ExprAssignedExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2')
    def __init__(self, field0: str, field1: ExprId, field2: ExprId) -> None: ...
    @property
    def field0(self) -> str: ...
    @property
    def field1(self) -> ExprId: ...
    @property
    def field2(self) -> ExprId: ...


class _ExprTupleExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[ExprId]) -> None: ...
    @property
    def field0(self) -> list[ExprId]: ...


class _ExprArrayExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[ExprId]) -> None: ...
    @property
    def field0(self) -> list[ExprId]: ...


class _ExprUnitExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ExprIfExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2')
    def __init__(self, field0: ExprId, field1: ExprId, field2: ExprId | None) -> None: ...
    @property
    def field0(self) -> ExprId: ...
    @property
    def field1(self) -> ExprId: ...
    @property
    def field2(self) -> ExprId | None: ...


class _ExprLetExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: list[PatId], field1: ExprId) -> None: ...
    @property
    def field0(self) -> list[PatId]: ...
    @property
    def field1(self) -> ExprId: ...


class _ExprMatchExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: ExprId | None, field1: list[MatchArm]) -> None: ...
    @property
    def field0(self) -> ExprId | None: ...
    @property
    def field1(self) -> list[MatchArm]: ...


class _ExprQuestMatchExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: ExprId, field1: list[MatchArm]) -> None: ...
    @property
    def field0(self) -> ExprId: ...
    @property
    def field1(self) -> list[MatchArm]: ...


class _ExprTryExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2', 'field3')
    def __init__(self, field0: list[Resource], field1: ExprId, field2: list[CatchArm], field3: ExprId | None) -> None: ...
    @property
    def field0(self) -> list[Resource]: ...
    @property
    def field1(self) -> ExprId: ...
    @property
    def field2(self) -> list[CatchArm]: ...
    @property
    def field3(self) -> ExprId | None: ...


class _ExprForExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2', 'field3')
    def __init__(self, field0: PatId, field1: ExprId, field2: ExprId | None, field3: ExprId) -> None: ...
    @property
    def field0(self) -> PatId: ...
    @property
    def field1(self) -> ExprId: ...
    @property
    def field2(self) -> ExprId | None: ...
    @property
    def field3(self) -> ExprId: ...


class _ExprWhileExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: ExprId, field1: ExprId) -> None: ...
    @property
    def field0(self) -> ExprId: ...
    @property
    def field1(self) -> ExprId: ...


class _ExprDoWhileExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: ExprId, field1: ExprId) -> None: ...
    @property
    def field0(self) -> ExprId: ...
    @property
    def field1(self) -> ExprId: ...


class _ExprThrowExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: ExprId) -> None: ...
    @property
    def field0(self) -> ExprId: ...


class _ExprReturnExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: ExprId | None) -> None: ...
    @property
    def field0(self) -> ExprId | None: ...


class _ExprBreakExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ExprContinueExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ExprSpawnExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: ExprId | None, field1: ExprId) -> None: ...
    @property
    def field0(self) -> ExprId | None: ...
    @property
    def field1(self) -> ExprId: ...


class _ExprSynchronizedExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: ExprId, field1: ExprId) -> None: ...
    @property
    def field0(self) -> ExprId: ...
    @property
    def field1(self) -> ExprId: ...


class _ExprUnsafeExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: ExprId) -> None: ...
    @property
    def field0(self) -> ExprId: ...


class _ExprLambdaExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: list[BodyParam], field1: ExprId) -> None: ...
    @property
    def field0(self) -> list[BodyParam]: ...
    @property
    def field1(self) -> ExprId: ...


class _ExprThisExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ExprSuperExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ExprWildcardExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ExprConvExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: str, field1: ExprId) -> None: ...
    @property
    def field0(self) -> str: ...
    @property
    def field1(self) -> ExprId: ...


class _ExprPrimExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: str) -> None: ...
    @property
    def field0(self) -> str: ...


class _ExprTypeExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: TypeRefId) -> None: ...
    @property
    def field0(self) -> TypeRefId: ...


class _ExprLangExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: LangItem) -> None: ...
    @property
    def field0(self) -> LangItem: ...


class _ExprBlockExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[Stmt]) -> None: ...
    @property
    def field0(self) -> list[Stmt]: ...


class _ExprQuoteExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[ExprId]) -> None: ...
    @property
    def field0(self) -> list[ExprId]: ...


class _ExprMacroExpr(Expr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: MacroCall) -> None: ...
    @property
    def field0(self) -> MacroCall: ...


class AttrArg(_Partial):
    @property
    def kind(self) -> str: ...
    DataArg: ClassVar[type[_AttrArgDataArg]]
    OptionArg: ClassVar[type[_AttrArgOptionArg]]
    ValueArg: ClassVar[type[_AttrArgValueArg]]
    TypesArg: ClassVar[type[_AttrArgTypesArg]]


class _AttrArgDataArg(AttrArg):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: ExprId | None, field1: ExprId) -> None: ...
    @property
    def field0(self) -> ExprId | None: ...
    @property
    def field1(self) -> ExprId: ...


class _AttrArgOptionArg(AttrArg):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: ExprId, field1: ExprId) -> None: ...
    @property
    def field0(self) -> ExprId: ...
    @property
    def field1(self) -> ExprId: ...


class _AttrArgValueArg(AttrArg):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: ExprId) -> None: ...
    @property
    def field0(self) -> ExprId: ...


class _AttrArgTypesArg(AttrArg):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: TypeRefId, field1: list[TypeRefId]) -> None: ...
    @property
    def field0(self) -> TypeRefId: ...
    @property
    def field1(self) -> list[TypeRefId]: ...


class Pat(_Partial):
    @property
    def kind(self) -> str: ...
    MissingPat: ClassVar[type[_PatMissingPat]]
    WildcardPat: ClassVar[type[_PatWildcardPat]]
    LitPat: ClassVar[type[_PatLitPat]]
    BindPat: ClassVar[type[_PatBindPat]]
    TypePat: ClassVar[type[_PatTypePat]]
    TuplePat: ClassVar[type[_PatTuplePat]]
    EnumPat: ClassVar[type[_PatEnumPat]]


class _PatMissingPat(Pat):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _PatWildcardPat(Pat):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _PatLitPat(Pat):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: str) -> None: ...
    @property
    def field0(self) -> str: ...


class _PatBindPat(Pat):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: LocalId) -> None: ...
    @property
    def field0(self) -> LocalId: ...


class _PatTypePat(Pat):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: LocalId | None, field1: TypeRefId) -> None: ...
    @property
    def field0(self) -> LocalId | None: ...
    @property
    def field1(self) -> TypeRefId: ...


class _PatTuplePat(Pat):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[PatId]) -> None: ...
    @property
    def field0(self) -> list[PatId]: ...


class _PatEnumPat(Pat):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: list[str], field1: list[PatId]) -> None: ...
    @property
    def field0(self) -> list[str]: ...
    @property
    def field1(self) -> list[PatId]: ...


class BodyOrigin(_Partial):
    @property
    def kind(self) -> str: ...
    @property
    def written(self) -> BodySource | None: ...
    WrittenSource: ClassVar[type[_BodyOriginWrittenSource]]
    SyntheticSource: ClassVar[type[_BodyOriginSyntheticSource]]


class _BodyOriginWrittenSource(BodyOrigin):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: BodySource) -> None: ...
    @property
    def field0(self) -> BodySource: ...


class _BodyOriginSyntheticSource(BodyOrigin):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class ValueTarget(_Partial):
    @property
    def kind(self) -> str: ...
    LocalOf: ClassVar[type[_ValueTargetLocalOf]]
    MemberOf: ClassVar[type[_ValueTargetMemberOf]]
    DeclOf: ClassVar[type[_ValueTargetDeclOf]]
    TypeParamOf: ClassVar[type[_ValueTargetTypeParamOf]]


class _ValueTargetLocalOf(ValueTarget):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: LocalId) -> None: ...
    @property
    def field0(self) -> LocalId: ...


class _ValueTargetMemberOf(ValueTarget):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: MemberTarget) -> None: ...
    @property
    def field0(self) -> MemberTarget: ...


class _ValueTargetDeclOf(ValueTarget):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: DefId) -> None: ...
    @property
    def field0(self) -> DefId: ...


class _ValueTargetTypeParamOf(ValueTarget):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: TypeTarget) -> None: ...
    @property
    def field0(self) -> TypeTarget: ...


class BodyResolution(_Partial):
    @property
    def kind(self) -> str: ...
    Values: ClassVar[type[_BodyResolutionValues]]
    InFile: ClassVar[type[_BodyResolutionInFile]]


class _BodyResolutionValues(BodyResolution):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[ValueTarget]) -> None: ...
    @property
    def field0(self) -> list[ValueTarget]: ...


class _BodyResolutionInFile(BodyResolution):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: Resolution) -> None: ...
    @property
    def field0(self) -> Resolution: ...


class CompilerType(_Partial):
    @property
    def kind(self) -> str: ...
    PointerType: ClassVar[type[_CompilerTypePointerType]]
    CStringType: ClassVar[type[_CompilerTypeCStringType]]
    RawArrayType: ClassVar[type[_CompilerTypeRawArrayType]]
    CFuncType: ClassVar[type[_CompilerTypeCFuncType]]
    VArrayType: ClassVar[type[_CompilerTypeVArrayType]]


class _CompilerTypePointerType(CompilerType):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _CompilerTypeCStringType(CompilerType):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _CompilerTypeRawArrayType(CompilerType):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _CompilerTypeCFuncType(CompilerType):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _CompilerTypeVArrayType(CompilerType):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class PackageRef(_Partial):
    @property
    def kind(self) -> str: ...
    Source: ClassVar[type[_PackageRefSource]]
    Binary: ClassVar[type[_PackageRefBinary]]


class _PackageRefSource(PackageRef):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: Package) -> None: ...
    @property
    def field0(self) -> Package: ...


class _PackageRefBinary(PackageRef):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: BinaryPackageFile) -> None: ...
    @property
    def field0(self) -> BinaryPackageFile: ...


class Visibility(_Partial):
    @property
    def kind(self) -> str: ...
    Private: ClassVar[type[_VisibilityPrivate]]
    Internal: ClassVar[type[_VisibilityInternal]]
    Protected: ClassVar[type[_VisibilityProtected]]
    Public: ClassVar[type[_VisibilityPublic]]


class _VisibilityPrivate(Visibility):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _VisibilityInternal(Visibility):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _VisibilityProtected(Visibility):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _VisibilityPublic(Visibility):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class ScopeStage(_Partial):
    @property
    def kind(self) -> str: ...
    Written: ClassVar[type[_ScopeStageWritten]]
    Expanded: ClassVar[type[_ScopeStageExpanded]]


class _ScopeStageWritten(ScopeStage):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ScopeStageExpanded(ScopeStage):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class ExpansionOrigin(_Partial):
    @property
    def kind(self) -> str: ...
    OfEntry: ClassVar[type[_ExpansionOriginOfEntry]]
    OfMacro: ClassVar[type[_ExpansionOriginOfMacro]]
    OfName: ClassVar[type[_ExpansionOriginOfName]]
    OfOption: ClassVar[type[_ExpansionOriginOfOption]]


class _ExpansionOriginOfEntry(ExpansionOrigin):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: int) -> None: ...
    @property
    def field0(self) -> int: ...


class _ExpansionOriginOfMacro(ExpansionOrigin):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ExpansionOriginOfName(ExpansionOrigin):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ExpansionOriginOfOption(ExpansionOrigin):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class ExpandTo(_Partial):
    @property
    def kind(self) -> str: ...
    ToItems: ClassVar[type[_ExpandToToItems]]
    ToExpr: ClassVar[type[_ExpandToToExpr]]
    ToStmts: ClassVar[type[_ExpandToToStmts]]


class _ExpandToToItems(ExpandTo):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ExpandToToExpr(ExpandTo):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ExpandToToStmts(ExpandTo):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class Receiver(_Partial):
    @property
    def kind(self) -> str: ...
    PackageReceiver: ClassVar[type[_ReceiverPackageReceiver]]
    TypesReceiver: ClassVar[type[_ReceiverTypesReceiver]]
    ValueReceiver: ClassVar[type[_ReceiverValueReceiver]]
    NoReceiver: ClassVar[type[_ReceiverNoReceiver]]


class _ReceiverPackageReceiver(Receiver):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: PackageRef) -> None: ...
    @property
    def field0(self) -> PackageRef: ...


class _ReceiverTypesReceiver(Receiver):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[ExtendedType]) -> None: ...
    @property
    def field0(self) -> list[ExtendedType]: ...


class _ReceiverValueReceiver(Receiver):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ReceiverNoReceiver(Receiver):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class FieldResolution(_Partial):
    @property
    def kind(self) -> str: ...
    PackageMembers: ClassVar[type[_FieldResolutionPackageMembers]]
    TypeMembers: ClassVar[type[_FieldResolutionTypeMembers]]
    OfValue: ClassVar[type[_FieldResolutionOfValue]]
    NoField: ClassVar[type[_FieldResolutionNoField]]


class _FieldResolutionPackageMembers(FieldResolution):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[DefId]) -> None: ...
    @property
    def field0(self) -> list[DefId]: ...


class _FieldResolutionTypeMembers(FieldResolution):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[MemberTarget]) -> None: ...
    @property
    def field0(self) -> list[MemberTarget]: ...


class _FieldResolutionOfValue(FieldResolution):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _FieldResolutionNoField(FieldResolution):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class PackageRelation(_Partial):
    @property
    def kind(self) -> str: ...
    SamePackage: ClassVar[type[_PackageRelationSamePackage]]
    Child: ClassVar[type[_PackageRelationChild]]
    SameModule: ClassVar[type[_PackageRelationSameModule]]
    Unrelated: ClassVar[type[_PackageRelationUnrelated]]


class _PackageRelationSamePackage(PackageRelation):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _PackageRelationChild(PackageRelation):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _PackageRelationSameModule(PackageRelation):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _PackageRelationUnrelated(PackageRelation):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class ImportError(_Partial):
    @property
    def kind(self) -> str: ...
    NoPackage: ClassVar[type[_ImportErrorNoPackage]]
    NotAccessible: ClassVar[type[_ImportErrorNotAccessible]]
    PackageReExported: ClassVar[type[_ImportErrorPackageReExported]]
    Cycle: ClassVar[type[_ImportErrorCycle]]
    SelfImport: ClassVar[type[_ImportErrorSelfImport]]


class _ImportErrorNoPackage(ImportError):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: str) -> None: ...
    @property
    def field0(self) -> str: ...


class _ImportErrorNotAccessible(ImportError):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: str, field1: str) -> None: ...
    @property
    def field0(self) -> str: ...
    @property
    def field1(self) -> str: ...


class _ImportErrorPackageReExported(ImportError):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: str) -> None: ...
    @property
    def field0(self) -> str: ...


class _ImportErrorCycle(ImportError):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: str) -> None: ...
    @property
    def field0(self) -> str: ...


class _ImportErrorSelfImport(ImportError):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: str) -> None: ...
    @property
    def field0(self) -> str: ...


class ImportTarget(_Partial):
    @property
    def kind(self) -> str: ...
    PackageOf: ClassVar[type[_ImportTargetPackageOf]]
    GlobOf: ClassVar[type[_ImportTargetGlobOf]]
    NameOf: ClassVar[type[_ImportTargetNameOf]]
    NoTarget: ClassVar[type[_ImportTargetNoTarget]]


class _ImportTargetPackageOf(ImportTarget):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: str, field1: PackageRef) -> None: ...
    @property
    def field0(self) -> str: ...
    @property
    def field1(self) -> PackageRef: ...


class _ImportTargetGlobOf(ImportTarget):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: PackageRef, field1: str) -> None: ...
    @property
    def field0(self) -> PackageRef: ...
    @property
    def field1(self) -> str: ...


class _ImportTargetNameOf(ImportTarget):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2', 'field3')
    def __init__(self, field0: PackageRef, field1: str, field2: str, field3: str | None) -> None: ...
    @property
    def field0(self) -> PackageRef: ...
    @property
    def field1(self) -> str: ...
    @property
    def field2(self) -> str: ...
    @property
    def field3(self) -> str | None: ...


class _ImportTargetNoTarget(ImportTarget):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: ImportError) -> None: ...
    @property
    def field0(self) -> ImportError: ...


class InferenceDiagnostic(_Partial):
    @property
    def kind(self) -> str: ...
    TypeMismatch: ClassVar[type[_InferenceDiagnosticTypeMismatch]]
    VArraySizeMismatch: ClassVar[type[_InferenceDiagnosticVArraySizeMismatch]]
    ArgCount: ClassVar[type[_InferenceDiagnosticArgCount]]
    ArgName: ClassVar[type[_InferenceDiagnosticArgName]]
    InvalidBinaryOperator: ClassVar[type[_InferenceDiagnosticInvalidBinaryOperator]]


class _InferenceDiagnosticTypeMismatch(InferenceDiagnostic):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2')
    def __init__(self, field0: ExprId, field1: Ty, field2: Ty) -> None: ...
    @property
    def field0(self) -> ExprId: ...
    @property
    def field1(self) -> Ty: ...
    @property
    def field2(self) -> Ty: ...


class _InferenceDiagnosticVArraySizeMismatch(InferenceDiagnostic):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2')
    def __init__(self, field0: ExprId, field1: int, field2: int) -> None: ...
    @property
    def field0(self) -> ExprId: ...
    @property
    def field1(self) -> int: ...
    @property
    def field2(self) -> int: ...


class _InferenceDiagnosticArgCount(InferenceDiagnostic):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2')
    def __init__(self, field0: ExprId, field1: list[Ty], field2: int) -> None: ...
    @property
    def field0(self) -> ExprId: ...
    @property
    def field1(self) -> list[Ty]: ...
    @property
    def field2(self) -> int: ...


class _InferenceDiagnosticArgName(InferenceDiagnostic):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2')
    def __init__(self, field0: ExprId, field1: int, field2: ArgNameError) -> None: ...
    @property
    def field0(self) -> ExprId: ...
    @property
    def field1(self) -> int: ...
    @property
    def field2(self) -> ArgNameError: ...


class _InferenceDiagnosticInvalidBinaryOperator(InferenceDiagnostic):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2')
    def __init__(self, field0: ExprId, field1: Ty, field2: Ty) -> None: ...
    @property
    def field0(self) -> ExprId: ...
    @property
    def field1(self) -> Ty: ...
    @property
    def field2(self) -> Ty: ...


class ArgNameError(_Partial):
    @property
    def kind(self) -> str: ...
    UnknownName: ClassVar[type[_ArgNameErrorUnknownName]]
    NameTwice: ClassVar[type[_ArgNameErrorNameTwice]]
    NeedsName: ClassVar[type[_ArgNameErrorNeedsName]]
    NameOfValue: ClassVar[type[_ArgNameErrorNameOfValue]]


class _ArgNameErrorUnknownName(ArgNameError):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: str) -> None: ...
    @property
    def field0(self) -> str: ...


class _ArgNameErrorNameTwice(ArgNameError):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: str) -> None: ...
    @property
    def field0(self) -> str: ...


class _ArgNameErrorNeedsName(ArgNameError):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[str]) -> None: ...
    @property
    def field0(self) -> list[str]: ...


class _ArgNameErrorNameOfValue(ArgNameError):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class ItemKind(_Partial):
    @property
    def kind(self) -> str: ...
    Import: ClassVar[type[_ItemKindImport]]
    Func: ClassVar[type[_ItemKindFunc]]
    Main: ClassVar[type[_ItemKindMain]]
    Macro: ClassVar[type[_ItemKindMacro]]
    Class: ClassVar[type[_ItemKindClass]]
    Interface: ClassVar[type[_ItemKindInterface]]
    Struct: ClassVar[type[_ItemKindStruct]]
    Enum: ClassVar[type[_ItemKindEnum]]
    Extend: ClassVar[type[_ItemKindExtend]]
    TypeAlias: ClassVar[type[_ItemKindTypeAlias]]
    Var: ClassVar[type[_ItemKindVar]]
    Prop: ClassVar[type[_ItemKindProp]]
    Init: ClassVar[type[_ItemKindInit]]
    Finalizer: ClassVar[type[_ItemKindFinalizer]]
    PrimaryInit: ClassVar[type[_ItemKindPrimaryInit]]
    EnumCtor: ClassVar[type[_ItemKindEnumCtor]]
    MacroCall: ClassVar[type[_ItemKindMacroCall]]
    BuiltIn: ClassVar[type[_ItemKindBuiltIn]]


class _ItemKindImport(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ItemKindFunc(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ItemKindMain(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ItemKindMacro(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ItemKindClass(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ItemKindInterface(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ItemKindStruct(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ItemKindEnum(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ItemKindExtend(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ItemKindTypeAlias(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ItemKindVar(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ItemKindProp(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ItemKindInit(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ItemKindFinalizer(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ItemKindPrimaryInit(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ItemKindEnumCtor(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ItemKindMacroCall(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ItemKindBuiltIn(ItemKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class Modifier(_Partial):
    @property
    def kind(self) -> str: ...
    Static: ClassVar[type[_ModifierStatic]]
    Public: ClassVar[type[_ModifierPublic]]
    Private: ClassVar[type[_ModifierPrivate]]
    Internal: ClassVar[type[_ModifierInternal]]
    Protected: ClassVar[type[_ModifierProtected]]
    Override: ClassVar[type[_ModifierOverride]]
    Redef: ClassVar[type[_ModifierRedef]]
    Abstract: ClassVar[type[_ModifierAbstract]]
    Sealed: ClassVar[type[_ModifierSealed]]
    Open: ClassVar[type[_ModifierOpen]]
    Foreign: ClassVar[type[_ModifierForeign]]
    Mut: ClassVar[type[_ModifierMut]]
    Unsafe: ClassVar[type[_ModifierUnsafe]]
    Operator: ClassVar[type[_ModifierOperator]]
    Const: ClassVar[type[_ModifierConst]]
    Common: ClassVar[type[_ModifierCommon]]
    Specific: ClassVar[type[_ModifierSpecific]]


class _ModifierStatic(Modifier):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ModifierPublic(Modifier):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ModifierPrivate(Modifier):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ModifierInternal(Modifier):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ModifierProtected(Modifier):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ModifierOverride(Modifier):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ModifierRedef(Modifier):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ModifierAbstract(Modifier):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ModifierSealed(Modifier):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ModifierOpen(Modifier):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ModifierForeign(Modifier):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ModifierMut(Modifier):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ModifierUnsafe(Modifier):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ModifierOperator(Modifier):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ModifierConst(Modifier):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ModifierCommon(Modifier):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _ModifierSpecific(Modifier):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class LangItem(_Partial):
    @property
    def kind(self) -> str: ...
    OptionEnum: ClassVar[type[_LangItemOptionEnum]]
    OptionSome: ClassVar[type[_LangItemOptionSome]]
    OptionNone: ClassVar[type[_LangItemOptionNone]]
    CompositionFunc: ClassVar[type[_LangItemCompositionFunc]]
    ObjectClass: ClassVar[type[_LangItemObjectClass]]
    StringStruct: ClassVar[type[_LangItemStringStruct]]
    FutureClass: ClassVar[type[_LangItemFutureClass]]
    IterableInterface: ClassVar[type[_LangItemIterableInterface]]
    RangeStruct: ClassVar[type[_LangItemRangeStruct]]
    ArrayStruct: ClassVar[type[_LangItemArrayStruct]]
    ExceptionClass: ClassVar[type[_LangItemExceptionClass]]
    TokensClass: ClassVar[type[_LangItemTokensClass]]
    AnyInterface: ClassVar[type[_LangItemAnyInterface]]


class _LangItemOptionEnum(LangItem):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LangItemOptionSome(LangItem):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LangItemOptionNone(LangItem):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LangItemCompositionFunc(LangItem):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LangItemObjectClass(LangItem):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LangItemStringStruct(LangItem):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LangItemFutureClass(LangItem):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LangItemIterableInterface(LangItem):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LangItemRangeStruct(LangItem):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LangItemArrayStruct(LangItem):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LangItemExceptionClass(LangItem):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LangItemTokensClass(LangItem):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _LangItemAnyInterface(LangItem):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class ExtendedType(_Partial):
    @property
    def kind(self) -> str: ...
    DeclType: ClassVar[type[_ExtendedTypeDeclType]]
    PrimType: ClassVar[type[_ExtendedTypePrimType]]
    BuiltInHead: ClassVar[type[_ExtendedTypeBuiltInHead]]


class _ExtendedTypeDeclType(ExtendedType):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: DefId) -> None: ...
    @property
    def field0(self) -> DefId: ...


class _ExtendedTypePrimType(ExtendedType):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: str) -> None: ...
    @property
    def field0(self) -> str: ...


class _ExtendedTypeBuiltInHead(ExtendedType):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: CompilerType) -> None: ...
    @property
    def field0(self) -> CompilerType: ...


class MemberTarget(_Partial):
    @property
    def kind(self) -> str: ...
    MemberDecl: ClassVar[type[_MemberTargetMemberDecl]]
    MemberParam: ClassVar[type[_MemberTargetMemberParam]]


class _MemberTargetMemberDecl(MemberTarget):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: DefId) -> None: ...
    @property
    def field0(self) -> DefId: ...


class _MemberTargetMemberParam(MemberTarget):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: DefId, field1: LocalId) -> None: ...
    @property
    def field0(self) -> DefId: ...
    @property
    def field1(self) -> LocalId: ...


class ScopeTarget(_Partial):
    @property
    def kind(self) -> str: ...
    OfDecl: ClassVar[type[_ScopeTargetOfDecl]]
    OfPackage: ClassVar[type[_ScopeTargetOfPackage]]


class _ScopeTargetOfDecl(ScopeTarget):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: DefId) -> None: ...
    @property
    def field0(self) -> DefId: ...


class _ScopeTargetOfPackage(ScopeTarget):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: PackageRef) -> None: ...
    @property
    def field0(self) -> PackageRef: ...


class Namespace(_Partial):
    @property
    def kind(self) -> str: ...
    Types: ClassVar[type[_NamespaceTypes]]
    Values: ClassVar[type[_NamespaceValues]]
    Macros: ClassVar[type[_NamespaceMacros]]


class _NamespaceTypes(Namespace):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _NamespaceValues(Namespace):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _NamespaceMacros(Namespace):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class Resolution(_Partial):
    @property
    def kind(self) -> str: ...
    Found: ClassVar[type[_ResolutionFound]]
    FoundPackage: ClassVar[type[_ResolutionFoundPackage]]
    Ambiguous: ClassVar[type[_ResolutionAmbiguous]]
    Ctors: ClassVar[type[_ResolutionCtors]]
    NotFound: ClassVar[type[_ResolutionNotFound]]


class _ResolutionFound(Resolution):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[DefId]) -> None: ...
    @property
    def field0(self) -> list[DefId]: ...


class _ResolutionFoundPackage(Resolution):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: PackageRef) -> None: ...
    @property
    def field0(self) -> PackageRef: ...


class _ResolutionAmbiguous(Resolution):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[ScopeTarget]) -> None: ...
    @property
    def field0(self) -> list[ScopeTarget]: ...


class _ResolutionCtors(Resolution):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: list[DefId], field1: list[DefId]) -> None: ...
    @property
    def field0(self) -> list[DefId]: ...
    @property
    def field1(self) -> list[DefId]: ...


class _ResolutionNotFound(Resolution):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class ScopeProblem(_Partial):
    @property
    def kind(self) -> str: ...
    ImportFailed: ClassVar[type[_ScopeProblemImportFailed]]
    Shadowed: ClassVar[type[_ScopeProblemShadowed]]
    Conflicted: ClassVar[type[_ScopeProblemConflicted]]
    SubPackage: ClassVar[type[_ScopeProblemSubPackage]]


class _ScopeProblemImportFailed(ScopeProblem):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: ImportError) -> None: ...
    @property
    def field0(self) -> ImportError: ...


class _ScopeProblemShadowed(ScopeProblem):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: str) -> None: ...
    @property
    def field0(self) -> str: ...


class _ScopeProblemConflicted(ScopeProblem):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: str) -> None: ...
    @property
    def field0(self) -> str: ...


class _ScopeProblemSubPackage(ScopeProblem):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: str, field1: str) -> None: ...
    @property
    def field0(self) -> str: ...
    @property
    def field1(self) -> str: ...


class ScopeProblemAt(_Partial):
    @property
    def kind(self) -> str: ...
    AtImport: ClassVar[type[_ScopeProblemAtAtImport]]
    AtDecl: ClassVar[type[_ScopeProblemAtAtDecl]]


class _ScopeProblemAtAtImport(ScopeProblemAt):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: ImportSite) -> None: ...
    @property
    def field0(self) -> ImportSite: ...


class _ScopeProblemAtAtDecl(ScopeProblemAt):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: DefId, field1: str) -> None: ...
    @property
    def field0(self) -> DefId: ...
    @property
    def field1(self) -> str: ...


class TypeRef(_Partial):
    @property
    def kind(self) -> str: ...
    PathRef: ClassVar[type[_TypeRefPathRef]]
    PrimRef: ClassVar[type[_TypeRefPrimRef]]
    TupleRef: ClassVar[type[_TypeRefTupleRef]]
    FuncRef: ClassVar[type[_TypeRefFuncRef]]
    OptionRef: ClassVar[type[_TypeRefOptionRef]]
    ThisRef: ClassVar[type[_TypeRefThisRef]]
    VArrayRef: ClassVar[type[_TypeRefVArrayRef]]
    MissingRef: ClassVar[type[_TypeRefMissingRef]]


class _TypeRefPathRef(TypeRef):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[TypeSegment]) -> None: ...
    @property
    def field0(self) -> list[TypeSegment]: ...


class _TypeRefPrimRef(TypeRef):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: str) -> None: ...
    @property
    def field0(self) -> str: ...


class _TypeRefTupleRef(TypeRef):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[TypeRefId]) -> None: ...
    @property
    def field0(self) -> list[TypeRefId]: ...


class _TypeRefFuncRef(TypeRef):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: list[TypeRefId], field1: TypeRefId) -> None: ...
    @property
    def field0(self) -> list[TypeRefId]: ...
    @property
    def field1(self) -> TypeRefId: ...


class _TypeRefOptionRef(TypeRef):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: TypeRefId) -> None: ...
    @property
    def field0(self) -> TypeRefId: ...


class _TypeRefThisRef(TypeRef):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _TypeRefVArrayRef(TypeRef):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: TypeRefId, field1: str | None) -> None: ...
    @property
    def field0(self) -> TypeRefId: ...
    @property
    def field1(self) -> str | None: ...


class _TypeRefMissingRef(TypeRef):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class TyErrorKind(_Partial):
    @property
    def kind(self) -> str: ...
    UndeclaredType: ClassVar[type[_TyErrorKindUndeclaredType]]
    NotAType: ClassVar[type[_TyErrorKindNotAType]]
    NeedsTypeArgs: ClassVar[type[_TyErrorKindNeedsTypeArgs]]
    WrongTypeArgCount: ClassVar[type[_TyErrorKindWrongTypeArgCount]]
    ThisNotAllowed: ClassVar[type[_TyErrorKindThisNotAllowed]]
    TypeCycle: ClassVar[type[_TyErrorKindTypeCycle]]


class _TyErrorKindUndeclaredType(TyErrorKind):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: str) -> None: ...
    @property
    def field0(self) -> str: ...


class _TyErrorKindNotAType(TyErrorKind):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: str) -> None: ...
    @property
    def field0(self) -> str: ...


class _TyErrorKindNeedsTypeArgs(TyErrorKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _TyErrorKindWrongTypeArgCount(TyErrorKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _TyErrorKindThisNotAllowed(TyErrorKind):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: bool) -> None: ...
    @property
    def field0(self) -> bool: ...


class _TyErrorKindTypeCycle(TyErrorKind):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[str]) -> None: ...
    @property
    def field0(self) -> list[str]: ...


class GenericOwner(_Partial):
    @property
    def kind(self) -> str: ...
    Declaration: ClassVar[type[_GenericOwnerDeclaration]]
    LocalFunction: ClassVar[type[_GenericOwnerLocalFunction]]


class _GenericOwnerDeclaration(GenericOwner):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: DefId) -> None: ...
    @property
    def field0(self) -> DefId: ...


class _GenericOwnerLocalFunction(GenericOwner):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: DefId, field1: int) -> None: ...
    @property
    def field0(self) -> DefId: ...
    @property
    def field1(self) -> int: ...


class TyKind(_Partial):
    """ErrorTy: user error; TodoTy: unsupported; UnknownTy: missing inputs/limits."""
    @property
    def kind(self) -> str: ...
    PrimTy: ClassVar[type[_TyKindPrimTy]]
    DeclTy: ClassVar[type[_TyKindDeclTy]]
    BuiltInTy: ClassVar[type[_TyKindBuiltInTy]]
    TupleTy: ClassVar[type[_TyKindTupleTy]]
    FuncTy: ClassVar[type[_TyKindFuncTy]]
    VArrayTy: ClassVar[type[_TyKindVArrayTy]]
    ParamTy: ClassVar[type[_TyKindParamTy]]
    ThisTy: ClassVar[type[_TyKindThisTy]]
    ErrorTy: ClassVar[type[_TyKindErrorTy]]
    TodoTy: ClassVar[type[_TyKindTodoTy]]
    UnknownTy: ClassVar[type[_TyKindUnknownTy]]
    InferTy: ClassVar[type[_TyKindInferTy]]


class _TyKindPrimTy(TyKind):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: str) -> None: ...
    @property
    def field0(self) -> str: ...


class _TyKindDeclTy(TyKind):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: DefId, field1: list[Ty]) -> None: ...
    @property
    def field0(self) -> DefId: ...
    @property
    def field1(self) -> list[Ty]: ...


class _TyKindBuiltInTy(TyKind):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: CompilerType, field1: list[Ty]) -> None: ...
    @property
    def field0(self) -> CompilerType: ...
    @property
    def field1(self) -> list[Ty]: ...


class _TyKindTupleTy(TyKind):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[Ty]) -> None: ...
    @property
    def field0(self) -> list[Ty]: ...


class _TyKindFuncTy(TyKind):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2')
    def __init__(self, field0: list[Ty], field1: Ty, field2: bool) -> None: ...
    @property
    def field0(self) -> list[Ty]: ...
    @property
    def field1(self) -> Ty: ...
    @property
    def field2(self) -> bool: ...


class _TyKindVArrayTy(TyKind):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: Ty, field1: int) -> None: ...
    @property
    def field0(self) -> Ty: ...
    @property
    def field1(self) -> int: ...


class _TyKindParamTy(TyKind):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: GenericOwner, field1: int) -> None: ...
    @property
    def field0(self) -> GenericOwner: ...
    @property
    def field1(self) -> int: ...


class _TyKindThisTy(TyKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _TyKindErrorTy(TyKind):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _TyKindTodoTy(TyKind):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: Todo) -> None: ...
    @property
    def field0(self) -> Todo: ...


class _TyKindUnknownTy(TyKind):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: UnknownReason) -> None: ...
    @property
    def field0(self) -> UnknownReason: ...


class _TyKindInferTy(TyKind):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: int) -> None: ...
    @property
    def field0(self) -> int: ...


class Todo(_Partial):
    @property
    def kind(self) -> str: ...
    MacroCall: ClassVar[type[_TodoMacroCall]]
    MacroMember: ClassVar[type[_TodoMacroMember]]


class _TodoMacroCall(Todo):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _TodoMacroMember(Todo):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class UnknownReason(_Partial):
    @property
    def kind(self) -> str: ...
    BinaryType: ClassVar[type[_UnknownReasonBinaryType]]
    NotInferred: ClassVar[type[_UnknownReasonNotInferred]]
    NoStd: ClassVar[type[_UnknownReasonNoStd]]
    GenericBoundsLimit: ClassVar[type[_UnknownReasonGenericBoundsLimit]]


class _UnknownReasonBinaryType(UnknownReason):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _UnknownReasonNotInferred(UnknownReason):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _UnknownReasonNoStd(UnknownReason):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class _UnknownReasonGenericBoundsLimit(UnknownReason):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class TypeTarget(_Partial):
    @property
    def kind(self) -> str: ...
    TypeOf: ClassVar[type[_TypeTargetTypeOf]]
    GenericOf: ClassVar[type[_TypeTargetGenericOf]]
    LocalGenericOf: ClassVar[type[_TypeTargetLocalGenericOf]]
    QualifierOf: ClassVar[type[_TypeTargetQualifierOf]]


class _TypeTargetTypeOf(TypeTarget):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: DefId) -> None: ...
    @property
    def field0(self) -> DefId: ...


class _TypeTargetGenericOf(TypeTarget):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: DefId, field1: int) -> None: ...
    @property
    def field0(self) -> DefId: ...
    @property
    def field1(self) -> int: ...


class _TypeTargetLocalGenericOf(TypeTarget):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2')
    def __init__(self, field0: DefId, field1: int, field2: int) -> None: ...
    @property
    def field0(self) -> DefId: ...
    @property
    def field1(self) -> int: ...
    @property
    def field2(self) -> int: ...


class _TypeTargetQualifierOf(TypeTarget):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: PackageRef) -> None: ...
    @property
    def field0(self) -> PackageRef: ...


class PathResolution(_Partial):
    @property
    def kind(self) -> str: ...
    Resolved: ClassVar[type[_PathResolutionResolved]]
    AmbiguousPath: ClassVar[type[_PathResolutionAmbiguousPath]]
    ConflictedPackages: ClassVar[type[_PathResolutionConflictedPackages]]
    UnresolvedPath: ClassVar[type[_PathResolutionUnresolvedPath]]


class _PathResolutionResolved(PathResolution):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: TypeTarget) -> None: ...
    @property
    def field0(self) -> TypeTarget: ...


class _PathResolutionAmbiguousPath(PathResolution):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[ScopeTarget]) -> None: ...
    @property
    def field0(self) -> list[ScopeTarget]: ...


class _PathResolutionConflictedPackages(PathResolution):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0',)
    def __init__(self, field0: list[PackageRef]) -> None: ...
    @property
    def field0(self) -> list[PackageRef]: ...


class _PathResolutionUnresolvedPath(PathResolution):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class CfgExpr(_Partial):
    @property
    def kind(self) -> str: ...
    CfgCompare: ClassVar[type[_CfgExprCfgCompare]]
    CfgFlag: ClassVar[type[_CfgExprCfgFlag]]
    CfgAnd: ClassVar[type[_CfgExprCfgAnd]]
    CfgOr: ClassVar[type[_CfgExprCfgOr]]
    CfgInvalid: ClassVar[type[_CfgExprCfgInvalid]]


class _CfgExprCfgCompare(CfgExpr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1', 'field2')
    def __init__(self, field0: str, field1: str, field2: str) -> None: ...
    @property
    def field0(self) -> str: ...
    @property
    def field1(self) -> str: ...
    @property
    def field2(self) -> str: ...


class _CfgExprCfgFlag(CfgExpr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: str, field1: bool) -> None: ...
    @property
    def field0(self) -> str: ...
    @property
    def field1(self) -> bool: ...


class _CfgExprCfgAnd(CfgExpr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: CfgExpr, field1: CfgExpr) -> None: ...
    @property
    def field0(self) -> CfgExpr: ...
    @property
    def field1(self) -> CfgExpr: ...


class _CfgExprCfgOr(CfgExpr):
    __match_args__: ClassVar[tuple[str, ...]] = ('field0', 'field1')
    def __init__(self, field0: CfgExpr, field1: CfgExpr) -> None: ...
    @property
    def field0(self) -> CfgExpr: ...
    @property
    def field1(self) -> CfgExpr: ...


class _CfgExprCfgInvalid(CfgExpr):
    __match_args__: ClassVar[tuple[str, ...]] = ()
    def __init__(self) -> None: ...


class BodyParam(_Partial):
    @property
    def local(self) -> LocalId | None: ...
    @property
    def ty(self) -> TypeRefId | None: ...
    @property
    def defaultValue(self) -> ExprId | None: ...
    @property
    def isMember(self) -> bool: ...
    @property
    def passedBy(self) -> str | None: ...


class LocalFunc(_Partial):
    @property
    def local(self) -> LocalId: ...
    @property
    def generics(self) -> list[str]: ...
    @property
    def params(self) -> list[BodyParam]: ...
    @property
    def ret(self) -> TypeRefId | None: ...
    @property
    def body(self) -> ExprId | None: ...
    @property
    def bounds(self) -> list[TypeBound]: ...


class CallArg(_Partial):
    @property
    def name(self) -> str | None: ...
    @property
    def expr(self) -> ExprId: ...
    @property
    def isInout(self) -> bool: ...
    @property
    def isTrailing(self) -> bool: ...


class MatchArm(_Partial):
    @property
    def pats(self) -> list[PatId]: ...
    @property
    def guard(self) -> ExprId | None: ...
    @property
    def condition(self) -> ExprId | None: ...
    @property
    def body(self) -> ExprId: ...


class Resource(_Partial):
    @property
    def local(self) -> LocalId | None: ...
    @property
    def ty(self) -> TypeRefId | None: ...
    @property
    def value(self) -> ExprId: ...


class CatchArm(_Partial):
    @property
    def local(self) -> LocalId | None: ...
    @property
    def types(self) -> list[TypeRefId]: ...
    @property
    def body(self) -> ExprId: ...


class MacroCall(_Partial):
    @property
    def path(self) -> list[str]: ...
    @property
    def attr(self) -> list[TypeRefId] | None: ...
    @property
    def args(self) -> list[CallArg]: ...


class DeclAttr(_Partial):
    @property
    def path(self) -> list[str]: ...
    @property
    def args(self) -> list[AttrArg]: ...


class TypeSegment(_Partial):
    @property
    def name(self) -> str: ...
    @property
    def args(self) -> list[TypeRefId]: ...


class TypeBound(_Partial):
    @property
    def ty(self) -> TypeRefId: ...
    @property
    def bounds(self) -> list[TypeRefId]: ...


class BinaryPackageFile: ...


class ImportSite(_Partial): ...


class Package: ...


class TyBound(_Partial): ...


class TyError(_Partial): ...


class TypePathTarget(_Partial): ...
