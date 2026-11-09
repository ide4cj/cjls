class SemanticSyntaxOrigin:
    """
    
    Exact syntax, synthetic HIR and unavailable source remain distinct when traversing back.
    
    """
    ...
    kind: Literal['SourceSyntax'] | Literal['SyntheticSyntax'] | Literal['UnavailableSyntax']
    class SourceSyntax(SemanticSyntaxOrigin):
        kind: Literal['SourceSyntax'] = 'SourceSyntax'
        def __init__(self, __p1: SemanticSyntaxElement):
            ...
        @readonly
        field0: SemanticSyntaxElement
        __match_args__ = ('field0')
    class SyntheticSyntax(SemanticSyntaxOrigin):
        kind: Literal['SyntheticSyntax'] = 'SyntheticSyntax'
        def __init__(self):
            ...
    class UnavailableSyntax(SemanticSyntaxOrigin):
        kind: Literal['UnavailableSyntax'] = 'UnavailableSyntax'
        def __init__(self):
            ...
class SemanticSyntaxMapping:
    """
    
    One exact syntax-to-HIR relationship. Several relationships may share either endpoint.
    
    """
    def __init__(self, __object: SemanticObject, __role: SemanticSyntaxRole):
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def object(self) -> SemanticObject:
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def role(self) -> SemanticSyntaxRole:
        ...
class SemanticSyntaxElement:
    """
    
    A node or token, including trivia and recovery nodes. Copied text/ranges describe this revision;
    retained elements reject operations after a write. Children/descendants preserve source order.
    
    """
    def kindName(self) -> str:
        """
        
        Native syntax kind name without exposing the generic syntax representation.
        @throws CancelledException - if inputs changed or analysis was cancelled.
        
        """
        ...
    def isToken(self) -> bool:
        ...
    def text(self) -> str:
        ...
    def location(self) -> SemanticLocation:
        """
         for type SemanticLocation, see 'loupe/semantic.pyi'
        """
        ...
    def parent(self) -> SemanticSyntaxElement | None:
        ...
    def children(self) -> list[SemanticSyntaxElement]:
        ...
    def descendants(self) -> list[SemanticSyntaxElement]:
        """
        
        Preorder including this element. No ancestor mapping or automatic macro descent occurs.
        
        """
        ...
    def pointer(self) -> SemanticSyntaxPointer | None:
        """
        
        Nodes have pointers; tokens remain checked views belonging to their containing tree.
        
        """
        ...
    def mappings(self) -> list[SemanticSyntaxMapping]:
        """
        
        Exact node mappings, never a nearest mapped ancestor. Tokens/unmapped nodes return [];
        unavailable trees return none from SemanticAnalysis.syntax. Declaration, signature type,
        expression, pattern, local and body type mappings appear in that order, each in arena
        order. Macro aliases retain their call-site role and expansion object identity.
        
        """
        ...
class SemanticSyntaxPointer:
    """
    
    A tree-free node handle qualified by its analysis and contextual file/expansion.
    Construction is confined to checked views; raw kind/range pairs cannot forge provenance.
    
    """
class SemanticSyntaxTree:
    """
    
    A request-owned lossless tree. Every view operation checks the originating analysis revision.
    Never store this tree or its elements in tracked results (A13); retain pointer() instead.
    
    """
    def root(self) -> SemanticSyntaxElement:
        ...
    def errors(self) -> list[SemanticSyntaxError]:
        ...
    def resolve(self, __pointer: SemanticSyntaxPointer) -> SemanticSyntaxElement | None:
        """
        
        Resolves only pointers issued by this analysis and contextual file, even when another
        tree has identical kind/range. Stale pointers throw CancelledException; foreign ones
        throw IllegalArgumentException before raw pointer resolution.
        
        """
        ...
class SemanticSyntaxError:
    """
    
    Parser recovery evidence bound to the tree's revision, including zero-width ranges.
    
    """
    def range(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    def message(self) -> str:
        ...
class SemanticSyntaxRole:
    """
    
    Direct mappings include declarations/types/bindings and the first written expression.
    Later expressions of the same syntax are desugared values; aliases link call sites to
    expansion objects whose canonical syntax remains inside the expansion.
    
    """
    ...
    kind: Literal['DirectSyntaxMapping'] | Literal['DesugaredSyntaxMapping'] | Literal['ExpansionAliasMapping']
    class DirectSyntaxMapping(SemanticSyntaxRole):
        kind: Literal['DirectSyntaxMapping'] = 'DirectSyntaxMapping'
        def __init__(self):
            ...
    class DesugaredSyntaxMapping(SemanticSyntaxRole):
        kind: Literal['DesugaredSyntaxMapping'] = 'DesugaredSyntaxMapping'
        def __init__(self):
            ...
    class ExpansionAliasMapping(SemanticSyntaxRole):
        kind: Literal['ExpansionAliasMapping'] = 'ExpansionAliasMapping'
        def __init__(self):
            ...
