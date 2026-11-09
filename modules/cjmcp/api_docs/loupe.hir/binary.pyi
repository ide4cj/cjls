class ItemFile:
    """
    
    Where an item is declared: a source file, a file of a package compiled already, by its index
    among the package's files, or the expansion of a macro call on an item of a source file (#175).
    CompilerBuiltIns supplies std.core's compiler-owned declarations without inventing source text.
    Name resolution takes each alike.
    
    """
    def __eq__(self, __other: ItemFile) -> bool:
        ...
    def __ne__(self, __other: ItemFile) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    kind: Literal['Source'] | Literal['Binary'] | Literal['Expansion'] | Literal['CompilerBuiltIns']
    class Source(ItemFile):
        kind: Literal['Source'] = 'Source'
        def __init__(self, __p1: SourceFile):
            """
             for type SourceFile, see 'loupe.db/db.pyi'
            """
            ...
        @readonly
        field0: SourceFile
        __match_args__ = ('field0')
    class Binary(ItemFile):
        kind: Literal['Binary'] = 'Binary'
        def __init__(self, __p1: BinaryPackageFile, __p2: int):
            """
             for type BinaryPackageFile, see 'loupe.db/project.pyi'
            """
            ...
        @readonly
        field0: BinaryPackageFile
        @readonly
        field1: int
        __match_args__ = ('field0', 'field1')
    class Expansion(ItemFile):
        kind: Literal['Expansion'] = 'Expansion'
        def __init__(self, __p1: MacroCallId):
            """
             for type MacroCallId, see 'loupe.hir/expansion.pyi'
            """
            ...
        @readonly
        field0: MacroCallId
        __match_args__ = ('field0')
    class CompilerBuiltIns(ItemFile):
        kind: Literal['CompilerBuiltIns'] = 'CompilerBuiltIns'
        def __init__(self, __p1: Package):
            """
             for type Package, see 'loupe.db/project.pyi'
            """
            ...
        @readonly
        field0: Package
        __match_args__ = ('field0')
class BinaryItem:
    """
    
    An item of a package compiled already: the index of its file, and its id there.
    
    """
    def __init__(self, __file: int, __id: ItemId):
        """
         for type ItemId, see 'loupe.hir/item_id.pyi'
        """
        ...
    @property
    def file(self) -> int:
        ...
    @property
    def id(self) -> ItemId:
        """
         for type ItemId, see 'loupe.hir/item_id.pyi'
        """
        ...
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: BinaryItem) -> bool:
        ...
    def __ne__(self, __other: BinaryItem) -> bool:
        ...
    def __hash__(self) -> int:
        ...
