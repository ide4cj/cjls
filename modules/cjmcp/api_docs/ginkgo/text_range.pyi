class TextRange:
    """
    
    A half-open range `[start, end)` of UTF-8 byte offsets into the text a tree was built from.
    
    """
    def __init__(self, __start: int, __end: int):
        """
        
        @throws IllegalArgumentException - if `start` is negative or past `end`
        
        """
        ...
    @property
    def start(self) -> int:
        ...
    @property
    def end(self) -> int:
        ...
    @staticmethod
    def at(__offset: int, __len: int) -> TextRange:
        ...
    @staticmethod
    def empty(__offset: int) -> TextRange:
        ...
    @property
    def len(self) -> int:
        ...
    def isEmpty(self) -> bool:
        ...
    def contains(self, __offset: int) -> bool:
        """
        
        Whether `offset` is inside, `end` excluded.
        
        """
        ...
    def containsInclusive(self, __offset: int) -> bool:
        """
        
        Whether `offset` is inside, `end` included.
        
        """
        ...
    def containsRange(self, __other: TextRange) -> bool:
        ...
    def intersect(self, __other: TextRange) -> TextRange | None:
        """
        
        The common part: empty when the two only touch, `None` when they are apart.
        
        """
        ...
    def cover(self, __other: TextRange) -> TextRange:
        """
        
        The smallest range containing both.
        
        """
        ...
    def shift(self, __by: int) -> TextRange:
        ...
    def __eq__(self, __other: TextRange) -> bool:
        ...
    def __ne__(self, __other: TextRange) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    def __repr__(self) -> str:
        ...
