from typing import Literal

class SemanticOwner:
    """
    A callable owner, or a contextual file when the occurrence is outside a callable. Local named functions and lambdas retain their own body identities.
    """
    ...
    kind: Literal['ObjectOwner', 'FileOwner']
    class ObjectOwner(SemanticOwner):
        kind: Literal['ObjectOwner'] = 'ObjectOwner'
        def __init__(self, __p1: SemanticObject):
            """
             for type SemanticObject, see 'loupe/semantic.pyi'
            """
            ...
        @property
        def field0(self) -> SemanticObject:
            ...
        __match_args__ = ('field0',)
    class FileOwner(SemanticOwner):
        kind: Literal['FileOwner'] = 'FileOwner'
        def __init__(self, __p1: ItemFile):
            """
             for type ItemFile, see 'loupe.hir/binary.pyi'
            """
            ...
        @property
        def field0(self) -> ItemFile:
            ...
        __match_args__ = ('field0',)
class SemanticUsage:
    """
    One semantic usage. Contextual locations are intentionally not deduplicated by physical path.
    """
    def __init__(self, __target: SemanticObject, __location: SemanticLocation, __owner: SemanticOwner, __access: ReferenceAccess | None, __isDeclaration: bool):
        """
         for type ReferenceAccess, see 'loupe/highlight_related.pyi'
         for type SemanticLocation, see 'loupe/semantic.pyi'
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def target(self) -> SemanticObject:
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def location(self) -> SemanticLocation:
        """
         for type SemanticLocation, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def owner(self) -> SemanticOwner:
        ...
    @property
    def access(self) -> ReferenceAccess | None:
        """
         for type ReferenceAccess, see 'loupe/highlight_related.pyi'
        """
        ...
    @property
    def isDeclaration(self) -> bool:
        ...
class SemanticUsages:
    """
    Written-source usages and explicit coverage omissions. Gaps are stable reason strings; macro-origin-usages means generated occurrences are outside the written reference model.
    """
    def __init__(self, __entries: list[SemanticUsage], __gaps: list[str]):
        ...
    @property
    def entries(self) -> list[SemanticUsage]:
        ...
    @property
    def gaps(self) -> list[str]:
        ...
class SemanticCallEdge:
    """
    A possible immediate call; candidate resolution and conservative dispatch survive composition.
    """
    def __init__(self, __caller: SemanticObject, __callee: SemanticObject, __site: SemanticLocation, __resolution: str, __isConservative: bool):
        """
         for type SemanticLocation, see 'loupe/semantic.pyi'
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def caller(self) -> SemanticObject:
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def callee(self) -> SemanticObject:
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def site(self) -> SemanticLocation:
        """
         for type SemanticLocation, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def resolution(self) -> str:
        ...
    @property
    def isConservative(self) -> bool:
        ...
class SemanticCallGap:
    """
    The original partial-call omission, retaining the caller's contextual source when available.
    """
    def __init__(self, __reason: str, __site: SemanticLocation | None):
        """
         for type SemanticLocation, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def reason(self) -> str:
        ...
    @property
    def site(self) -> SemanticLocation | None:
        """
         for type SemanticLocation, see 'loupe/semantic.pyi'
        """
        ...
class SemanticCalls:
    """
    Immediate possible calls and explicit omissions; absence never proves runtime purity (A39).
    """
    def __init__(self, __edges: list[SemanticCallEdge], __gaps: list[SemanticCallGap]):
        ...
    @property
    def edges(self) -> list[SemanticCallEdge]:
        ...
    @property
    def gaps(self) -> list[SemanticCallGap]:
        ...
class SemanticHierarchyEdge:
    """
    A direct inheritance edge. Owner is the declaration writing the supertype; an extend also records its provenance independently of the type it extends.
    """
    def __init__(self, __subtype: SemanticObject, __supertype: SemanticObject, __owner: SemanticObject, __extension: SemanticObject | None):
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def subtype(self) -> SemanticObject:
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def supertype(self) -> SemanticObject:
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def owner(self) -> SemanticObject:
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def extension(self) -> SemanticObject | None:
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
class SemanticImplementationEdge:
    """
    An immediate overridden/implemented member, with the implementing member's declaration owner.
    """
    def __init__(self, __implementation: SemanticObject, __declaration: SemanticObject, __owner: SemanticObject, __extension: SemanticObject | None):
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def implementation(self) -> SemanticObject:
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def declaration(self) -> SemanticObject:
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def owner(self) -> SemanticObject:
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def extension(self) -> SemanticObject | None:
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
