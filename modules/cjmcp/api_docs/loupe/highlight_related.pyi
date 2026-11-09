class RelatedHighlight:
    """
    
    A name of the file meaning what the one asked about does, and how it reaches it; `None` for a name
    that neither reads nor writes: a declaration but of a `var`, a name in a type or a pattern.
    
    """
    def __init__(self, __range: TextRange, __access: ReferenceAccess | None):
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
    def access(self) -> ReferenceAccess | None:
        ...
    def __eq__(self, __other: RelatedHighlight) -> bool:
        ...
    def __ne__(self, __other: RelatedHighlight) -> bool:
        ...
class ReferenceAccess:
    """
    
    How a name reaches what it means: reads it, or gives it a value.
    
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: ReferenceAccess) -> bool:
        ...
    def __ne__(self, __other: ReferenceAccess) -> bool:
        ...
    kind: Literal['ReadAccess'] | Literal['WriteAccess']
    class ReadAccess(ReferenceAccess):
        kind: Literal['ReadAccess'] = 'ReadAccess'
        def __init__(self):
            ...
    class WriteAccess(ReferenceAccess):
        kind: Literal['WriteAccess'] = 'WriteAccess'
        def __init__(self):
            ...
