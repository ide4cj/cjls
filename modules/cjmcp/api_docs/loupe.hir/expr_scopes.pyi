class ScopeId:
    """
    
    A scope of a body, by its place among the body's scopes.
    
    """
    def __init__(self, __index: int):
        ...
    @property
    def index(self) -> int:
        ...
    def __eq__(self, __other: ScopeId) -> bool:
        ...
    def __ne__(self, __other: ScopeId) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    def __repr__(self) -> str:
        ...
class ScopeData:
    """
    
    A scope: the one around it, and the locals it adds; a local function's own has its type
    parameters.
    
    """
    def __init__(self, __parent: ScopeId | None, __entries: list[LocalId], *, genericsOf: int | None = ..., generics: list[str] = ...):
        """
         for type LocalId, see 'loupe.hir/body.pyi'
        """
        ...
    @property
    def parent(self) -> ScopeId | None:
        ...
    @property
    def entries(self) -> list[LocalId]:
        """
         for type LocalId, see 'loupe.hir/body.pyi'
        """
        ...
    @property
    def genericsOf(self) -> int | None:
        ...
    @property
    def generics(self) -> list[str]:
        ...
    def __eq__(self, __other: ScopeData) -> bool:
        ...
    def __ne__(self, __other: ScopeData) -> bool:
        ...
class ExprScopes:
    """
    
    The scopes of a body, rust-analyzer's `ExprScopes`: a tree, and where each expression and type is,
    the scope it sees. A declaration opens a scope for what follows it, its initializer not in it:
    what comes before a local, and the local's own initializer, see what is around it (N60, N61). A
    block and the bindings before it are one scope in cjc, which only says so for a redefinition
    (N59); here they nest, which answers a lookup the same.
    
    """
    def __init__(self, *, scopes: list[ScopeData] = ..., exprScopes: list[ScopeId | None] = ..., typeScopes: list[ScopeId | None] = ...):
        ...
    @property
    def scopes(self) -> list[ScopeData]:
        ...
    @property
    def exprScopes(self) -> list[ScopeId | None]:
        ...
    @property
    def typeScopes(self) -> list[ScopeId | None]:
        ...
    def __getitem__(self, __id: ScopeId) -> ScopeData:
        ...
    def scopeOf(self, __expr: ExprId) -> ScopeId | None:
        """
        
        The scope `expr` sees, `None` for one of no body.
        
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    def scopeOfType(self, __ty: TypeRefId) -> ScopeId | None:
        """
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    def chain(self, __scope: ScopeId | None) -> list[ScopeId]:
        """
        
        The scopes from `scope` out, it first.
        
        """
        ...
    def __eq__(self, __other: ExprScopes) -> bool:
        ...
    def __ne__(self, __other: ExprScopes) -> bool:
        ...
