from typing import Literal

class SemanticOrigin:
    """
    Exact syntax, synthetic HIR and unavailable source are distinct, including for binaries.
    """
    ...
    kind: Literal['SourceOrigin', 'SyntheticOrigin', 'UnavailableOrigin']
    class SourceOrigin(SemanticOrigin):
        kind: Literal['SourceOrigin'] = 'SourceOrigin'
        def __init__(self, __p1: SemanticLocation):
            ...
        @property
        def field0(self) -> SemanticLocation:
            ...
        __match_args__ = ('field0')
    class SyntheticOrigin(SemanticOrigin):
        kind: Literal['SyntheticOrigin'] = 'SyntheticOrigin'
        def __init__(self):
            ...
    class UnavailableOrigin(SemanticOrigin):
        kind: Literal['UnavailableOrigin'] = 'UnavailableOrigin'
        def __init__(self):
            ...
class SemanticIdentity:
    """
    An identity within one database revision. Body indices carry their declaration owner; signature and body types occupy different arenas. Do not reuse after edits/reloads or in another database. Keep SemanticObject when composing queries: it retains the snapshot. Local definitions are normalized to LocalIdentity, including when reached through resolution. Explicit initializers retain their own declaration identity independently of navigation.
    """
    def __eq__(self, __other: SemanticIdentity) -> bool:
        ...
    def __ne__(self, __other: SemanticIdentity) -> bool:
        ...
    kind: Literal['NamedIdentity', 'ExpressionIdentity', 'PatternIdentity', 'LocalIdentity', 'SignatureTypeIdentity', 'BodyTypeIdentity']
    class NamedIdentity(SemanticIdentity):
        kind: Literal['NamedIdentity'] = 'NamedIdentity'
        def __init__(self, __p1: Definition):
            """
             for type Definition, see 'loupe/defs.pyi'
            """
            ...
        @property
        def field0(self) -> Definition:
            ...
        __match_args__ = ('field0')
    class ExpressionIdentity(SemanticIdentity):
        kind: Literal['ExpressionIdentity'] = 'ExpressionIdentity'
        def __init__(self, __p1: DefId, __p2: ExprId):
            """
             for type ExprId, see 'loupe.hir/body.pyi'
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        @property
        def field1(self) -> ExprId:
            ...
        __match_args__ = ('field0', 'field1')
    class PatternIdentity(SemanticIdentity):
        kind: Literal['PatternIdentity'] = 'PatternIdentity'
        def __init__(self, __p1: DefId, __p2: PatId):
            """
             for type PatId, see 'loupe.hir/body.pyi'
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        @property
        def field1(self) -> PatId:
            ...
        __match_args__ = ('field0', 'field1')
    class LocalIdentity(SemanticIdentity):
        kind: Literal['LocalIdentity'] = 'LocalIdentity'
        def __init__(self, __p1: DefId, __p2: LocalId):
            """
             for type LocalId, see 'loupe.hir/body.pyi'
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        @property
        def field1(self) -> LocalId:
            ...
        __match_args__ = ('field0', 'field1')
    class SignatureTypeIdentity(SemanticIdentity):
        kind: Literal['SignatureTypeIdentity'] = 'SignatureTypeIdentity'
        def __init__(self, __p1: DefId, __p2: TypeRefId):
            """
             for type TypeRefId, see 'loupe.hir/signature.pyi'
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        @property
        def field1(self) -> TypeRefId:
            ...
        __match_args__ = ('field0', 'field1')
    class BodyTypeIdentity(SemanticIdentity):
        kind: Literal['BodyTypeIdentity'] = 'BodyTypeIdentity'
        def __init__(self, __p1: DefId, __p2: TypeRefId):
            """
             for type TypeRefId, see 'loupe.hir/signature.pyi'
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        @property
        def field1(self) -> TypeRefId:
            ...
        __match_args__ = ('field0', 'field1')
class SemanticSourceKind:
    """
    Source text may be physical workspace/dependency text, a checked attachment, or macro output.
    """
    def __eq__(self, __other: SemanticSourceKind) -> bool:
        ...
    def __ne__(self, __other: SemanticSourceKind) -> bool:
        ...
    kind: Literal['PhysicalSource', 'AttachedSource', 'ExpansionSource']
    class PhysicalSource(SemanticSourceKind):
        kind: Literal['PhysicalSource'] = 'PhysicalSource'
        def __init__(self):
            ...
    class AttachedSource(SemanticSourceKind):
        kind: Literal['AttachedSource'] = 'AttachedSource'
        def __init__(self):
            ...
    class ExpansionSource(SemanticSourceKind):
        kind: Literal['ExpansionSource'] = 'ExpansionSource'
        def __init__(self):
            ...
class SemanticAnalysis:
    """
    Analysis pinned to db's current revision, used from one thread at a time. All object, location, type and text operations use this snapshot and throw CancelledException after an input write or request cancellation. No operation reopens disk. Copied text, coordinates and identities describe only the originating revision.
    """
    def at(self, __fileId: FileId, __offset: int) -> SemanticOccurrence | None:
        """
        UTF-8 byte offset in the editor's preferred context; none for an unavailable file.
         for type FileId, see 'loupe.vfs/vfs.pyi'
        """
        ...
    def inFile(self, __file: ItemFile, __offset: int) -> SemanticOccurrence | None:
        """
        Preserves explicit source context/expansion. At a boundary prefers right name, left name, right operator, left operator; otherwise the right token (last token at EOF). Selects the nearest mapped ancestor of each HIR category, before desugaring. Out-of-range offsets return none. File identities must belong to this database and revision. Source macro arguments do not descend into expansions (#370).
         for type ItemFile, see 'loupe.hir/binary.pyi'
        """
        ...
class SemanticOccurrence:
    """
    Occurrence and targets are distinct. Definitions preserves zero/one/many meanings: none is unavailable/inapplicable classification, an empty array a known empty result. Objects contains the nearest mapped node of each HIR category. Written type references retain their own identity.
    """
    @property
    def location(self) -> SemanticLocation:
        ...
    @property
    def owner(self) -> SemanticObject | None:
        ...
    @property
    def definitions(self) -> list[SemanticObject] | None:
        ...
    @property
    def objects(self) -> list[SemanticObject]:
        ...
    def __init__(self, __analysis: SemanticAnalysis, __location: SemanticLocation, __owner: SemanticObject | None, __definitions: list[SemanticObject] | None, __objects: list[SemanticObject]):
        ...
class SemanticObject:
    """
    A semantic object bound to its originating snapshot, independently of navigation targets.
    """
    @property
    def identity(self) -> SemanticIdentity:
        ...
    def origins(self) -> list[SemanticOrigin]:
        """
        Exact syntax origins. A package can have several headers; binary source must pass the existing identity check. Generated syntax stays in its expansion, never an approximate head.
        """
        ...
    def semanticType(self) -> SemanticType | None:
        """
        Inferred/resolved type bound to this object's snapshot, retaining structured unknown/error reasons; none when inapplicable. Child types and definitions use the same context.
         for type SemanticType, see 'loupe/semantic_type.pyi'
        """
        ...
    def typeDisplay(self) -> str | None:
        """
        Type display from this object's revision; none when it has no type.
        """
        ...
class SemanticLocation:
    """
    Contextual source/expansion location bound to the snapshot. Ranges are end-exclusive UTF-8 bytes. Expansion text and attached source retain their distinct ItemFile identity.
    """
    @property
    def file(self) -> ItemFile:
        """
         for type ItemFile, see 'loupe.hir/binary.pyi'
        """
        ...
    @property
    def fullRange(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def focusRange(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    def kind(self) -> SemanticSourceKind:
        """
        Distinguishes attached source from physical source and generated expansion text.
        """
        ...
    def sourceText(self) -> str | None:
        """
        Immutable file/expansion text copied from this revision. @throws CancelledException - if inputs changed or analysis was cancelled.
        """
        ...
    def coordinates(self) -> tuple[int, int] | None:
        """
        Zero-based line and UTF-8 byte column of the focus start. @throws CancelledException - if inputs changed or analysis was cancelled.
        """
        ...
    def excerpt(self, *, full: bool = ...) -> str | None:
        """
        Exact focus text (or full syntax with full: true), read from the same snapshot.
        """
        ...
    def compact(self) -> str | None:
        """
        Compact zero-based line:UTF-8-byte-column.
        """
        ...
    def source(self) -> SemanticLocation | None:
        """
        Physical/attached source or an exact copied expansion span; none for generated text.
        """
        ...
