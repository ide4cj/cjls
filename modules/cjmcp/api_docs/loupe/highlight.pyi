class HighlightedRange:
    """
    
    A token of a file and what it is. `range` is in UTF-8 bytes (A6).
    
    """
    def __init__(self, __range: TextRange, __tag: HighlightTag, *, modifiers: HighlightModifiers = ...):
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def range(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def tag(self) -> HighlightTag:
        ...
    @property
    def modifiers(self) -> HighlightModifiers:
        ...
    def __repr__(self) -> str:
        """
        
        `tag[modifiers]@start..end`.
        
        """
        ...
    def __eq__(self, __other: HighlightedRange) -> bool:
        ...
    def __ne__(self, __other: HighlightedRange) -> bool:
        ...
class HighlightModifiers:
    """
    
    A set of `HighlightModifier`s.
    
    """
    def plus(self, __modifier: HighlightModifier) -> HighlightModifiers:
        ...
    def contains(self, __modifier: HighlightModifier) -> bool:
        ...
    def isEmpty(self) -> bool:
        ...
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: HighlightModifiers) -> bool:
        ...
    def __ne__(self, __other: HighlightModifiers) -> bool:
        ...
class HighlightTag:
    """
    
    What a token is: by the tree, and a name at its use by what it means (D72). In a file of no
    package, which names do not resolve in, a name inside a type is taken for one.
    
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: HighlightTag) -> bool:
        ...
    def __ne__(self, __other: HighlightTag) -> bool:
        ...
    kind: Literal['Keyword'] | Literal['Comment'] | Literal['StringLiteral'] | Literal['NumberLiteral'] | Literal['Operator'] | Literal['InterpolationDelimiter'] | Literal['BuiltinAnnotation'] | Literal['MacroCall'] | Literal['BuiltinType'] | Literal['TypeName'] | Literal['TypeParameter'] | Literal['Parameter'] | Literal['Symbol'] | Literal['Namespace'] | Literal['UnresolvedReference']
    class Keyword(HighlightTag):
        kind: Literal['Keyword'] = 'Keyword'
        def __init__(self):
            ...
    class Comment(HighlightTag):
        kind: Literal['Comment'] = 'Comment'
        def __init__(self):
            ...
    class StringLiteral(HighlightTag):
        kind: Literal['StringLiteral'] = 'StringLiteral'
        def __init__(self):
            ...
    class NumberLiteral(HighlightTag):
        kind: Literal['NumberLiteral'] = 'NumberLiteral'
        def __init__(self):
            ...
    class Operator(HighlightTag):
        kind: Literal['Operator'] = 'Operator'
        def __init__(self):
            ...
    class InterpolationDelimiter(HighlightTag):
        kind: Literal['InterpolationDelimiter'] = 'InterpolationDelimiter'
        def __init__(self):
            ...
    class BuiltinAnnotation(HighlightTag):
        kind: Literal['BuiltinAnnotation'] = 'BuiltinAnnotation'
        def __init__(self):
            ...
    class MacroCall(HighlightTag):
        kind: Literal['MacroCall'] = 'MacroCall'
        def __init__(self):
            ...
    class BuiltinType(HighlightTag):
        kind: Literal['BuiltinType'] = 'BuiltinType'
        def __init__(self):
            ...
    class TypeName(HighlightTag):
        kind: Literal['TypeName'] = 'TypeName'
        def __init__(self):
            ...
    class TypeParameter(HighlightTag):
        kind: Literal['TypeParameter'] = 'TypeParameter'
        def __init__(self):
            ...
    class Parameter(HighlightTag):
        kind: Literal['Parameter'] = 'Parameter'
        def __init__(self):
            ...
    class Symbol(HighlightTag):
        kind: Literal['Symbol'] = 'Symbol'
        def __init__(self, __p1: StructureKind):
            """
             for type StructureKind, see 'loupe/structure.pyi'
            """
            ...
        @readonly
        field0: StructureKind
        __match_args__ = ('field0')
    class Namespace(HighlightTag):
        kind: Literal['Namespace'] = 'Namespace'
        def __init__(self):
            ...
    class UnresolvedReference(HighlightTag):
        kind: Literal['UnresolvedReference'] = 'UnresolvedReference'
        def __init__(self):
            ...
class HighlightModifier:
    def bit(self) -> int:
        ...
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: HighlightModifier) -> bool:
        ...
    def __ne__(self, __other: HighlightModifier) -> bool:
        ...
    kind: Literal['Declaration'] | Literal['Documentation'] | Literal['Readonly'] | Literal['Static'] | Literal['Deprecated'] | Literal['DefaultLibrary'] | Literal['Mutable']
    class Declaration(HighlightModifier):
        kind: Literal['Declaration'] = 'Declaration'
        def __init__(self):
            ...
    class Documentation(HighlightModifier):
        kind: Literal['Documentation'] = 'Documentation'
        def __init__(self):
            ...
    class Readonly(HighlightModifier):
        kind: Literal['Readonly'] = 'Readonly'
        def __init__(self):
            ...
    class Static(HighlightModifier):
        kind: Literal['Static'] = 'Static'
        def __init__(self):
            ...
    class Deprecated(HighlightModifier):
        kind: Literal['Deprecated'] = 'Deprecated'
        def __init__(self):
            ...
    class DefaultLibrary(HighlightModifier):
        kind: Literal['DefaultLibrary'] = 'DefaultLibrary'
        def __init__(self):
            ...
    class Mutable(HighlightModifier):
        kind: Literal['Mutable'] = 'Mutable'
        def __init__(self):
            ...
