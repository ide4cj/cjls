class CallDeclaration:
    """
    
    Canonical declaration metadata, with an optional navigation location. Match targets by identity
    and ownership rather than source spelling: package ownership is independent of import aliases.
    Declaration identities belong to their producing analysis database and revision.
    
    """
    def __init__(self, __definition: DefId, __packageName: str, __name: str, __ownerName: str, __location: NavigationTarget | None):
        """
         for type NavigationTarget, see 'loupe/definition.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def definition(self) -> DefId:
        """
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def packageName(self) -> str:
        ...
    @property
    def name(self) -> str:
        ...
    @property
    def ownerName(self) -> str:
        ...
    @property
    def location(self) -> NavigationTarget | None:
        """
         for type NavigationTarget, see 'loupe/definition.pyi'
        """
        ...
class DirectCall:
    """
    
    A possible immediate call at a UTF-8 source site. Targets belong to the producing database/revision.
    `resolution` is `resolved-declaration` for an explicit call, `inferred-operator` for a selected
    operator overload, or `candidate` for an ambiguous or virtual target. A candidate has
    `isConservative` set; any chain containing it must retain that qualification.
    
    """
    def __init__(self, __target: DefId, __site: NavigationTarget, __resolution: str, *, isConservative: bool):
        """
         for type NavigationTarget, see 'loupe/definition.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def target(self) -> DefId:
        """
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def site(self) -> NavigationTarget:
        """
         for type NavigationTarget, see 'loupe/definition.pyi'
        """
        ...
    @property
    def resolution(self) -> str:
        ...
    @property
    def isConservative(self) -> bool:
        ...
    def __eq__(self, __other: DirectCall) -> bool:
        ...
    def __ne__(self, __other: DirectCall) -> bool:
        ...
class CallGap:
    """
    
    Coverage information, not a source diagnostic. A missing body may have no source site.
    Stable `reason` strings identify the omitted behavior:
    - `unavailable-body`: binary/expansion body, absent block or removed declaration.
    - `unresolved-call`: no declaration-backed callable target resolved.
    - `functional-value`: invocation of a local function, lambda, parameter, variable or expression.
    - `functional-value-or-constructor`: a value/type without a selected callable declaration.
    - `callback-flow`: a call has arguments; callback transfer/invocation is not modeled.
    This deliberately includes arguments that are not callbacks.
    - `virtual-dispatch`: possible runtime implementations of a static target are not enumerated.
    - `implicit-initialization`: field, base or other implicit construction effects.
    - `implicit-operator`: operator effects are incomplete, even with a selected overload edge.
    - `property-or-initialization`: getter/setter or declaration-backed value initialization.
    - `unresolved-value`: value resolution is unavailable.
    - `default-arguments`: default values are not unconditional body calls.
    - `implicit-conversion`: interpolation may invoke user conversion code.
    - `malformed-source`: parse recovery may have omitted executable code.
    - `iteration-protocol`, `resource-protocol`, `spawn-boundary`: implicit protocol/execution effects.
    - `declaration-macro`, `body-macro`: macro behavior outside the transparent CalcaTracked policy.
    
    """
    def __init__(self, __reason: str, __site: NavigationTarget | None):
        """
         for type NavigationTarget, see 'loupe/definition.pyi'
        """
        ...
    @property
    def reason(self) -> str:
        ...
    @property
    def site(self) -> NavigationTarget | None:
        """
         for type NavigationTarget, see 'loupe/definition.pyi'
        """
        ...
    def __eq__(self, __other: CallGap) -> bool:
        ...
    def __ne__(self, __other: CallGap) -> bool:
        ...
class DirectCalls:
    """
    
    Immediate edges and omissions in a partial possible-call model. Both conditional branches
    contribute; edges do not prove execution. Empty edges with gaps leave reachability unknown.
    Even a traversal without gaps establishes absence only within this model: compiler/runtime
    effects such as allocation, finalization and implicit string conversion may remain unmodeled.
    This result cannot certify general language-level purity.
    
    """
    def __init__(self, __edges: list[DirectCall], __gaps: list[CallGap]):
        ...
    @property
    def edges(self) -> list[DirectCall]:
        ...
    @property
    def gaps(self) -> list[CallGap]:
        ...
    def __eq__(self, __other: DirectCalls) -> bool:
        ...
    def __ne__(self, __other: DirectCalls) -> bool:
        ...
