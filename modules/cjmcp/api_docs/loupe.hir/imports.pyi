class PackageRelation:
    """
    
    How a package that refers to a declaration stands to the package declaring it, cjc's
    `PackageRelation`: the same, one under it by name (`m.a.b` to `m.a`), one of the same first
    segment (cjc's module), or none of these.
    
    """
    def __eq__(self, __other: PackageRelation) -> bool:
        ...
    def __ne__(self, __other: PackageRelation) -> bool:
        ...
    kind: Literal['SamePackage'] | Literal['Child'] | Literal['SameModule'] | Literal['Unrelated']
    class SamePackage(PackageRelation):
        kind: Literal['SamePackage'] = 'SamePackage'
        def __init__(self):
            ...
    class Child(PackageRelation):
        kind: Literal['Child'] = 'Child'
        def __init__(self):
            ...
    class SameModule(PackageRelation):
        kind: Literal['SameModule'] = 'SameModule'
        def __init__(self):
            ...
    class Unrelated(PackageRelation):
        kind: Literal['Unrelated'] = 'Unrelated'
        def __init__(self):
            ...
class IndexedPackage:
    """
    
    A package of the project and who it is of: a module's name, or a binary's.
    
    """
    def __init__(self, __pkg: PackageRef, __owner: str):
        """
         for type PackageRef, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def pkg(self) -> PackageRef:
        """
         for type PackageRef, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def owner(self) -> str:
        ...
    def __eq__(self, __other: IndexedPackage) -> bool:
        ...
    def __ne__(self, __other: IndexedPackage) -> bool:
        ...
class ImportError:
    """
    
    Why a path of an import brings nothing, as cjpm and cjc report it.
    
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: ImportError) -> bool:
        ...
    def __ne__(self, __other: ImportError) -> bool:
        ...
    kind: Literal['NoPackage'] | Literal['NotAccessible'] | Literal['PackageReExported'] | Literal['Cycle'] | Literal['SelfImport']
    class NoPackage(ImportError):
        kind: Literal['NoPackage'] = 'NoPackage'
        def __init__(self, __p1: str):
            ...
        @readonly
        field0: str
        __match_args__ = ('field0')
    class NotAccessible(ImportError):
        kind: Literal['NotAccessible'] = 'NotAccessible'
        def __init__(self, __p1: str, __p2: str):
            ...
        @readonly
        field0: str
        @readonly
        field1: str
        __match_args__ = ('field0', 'field1')
    class PackageReExported(ImportError):
        kind: Literal['PackageReExported'] = 'PackageReExported'
        def __init__(self, __p1: str):
            ...
        @readonly
        field0: str
        __match_args__ = ('field0')
    class Cycle(ImportError):
        kind: Literal['Cycle'] = 'Cycle'
        def __init__(self, __p1: str):
            ...
        @readonly
        field0: str
        __match_args__ = ('field0')
    class SelfImport(ImportError):
        kind: Literal['SelfImport'] = 'SelfImport'
        def __init__(self, __p1: str):
            ...
        @readonly
        field0: str
        __match_args__ = ('field0')
class ImportTarget:
    """
    
    What a path of an import names, before the names it brings are read: a package, every name of
    one, or one name of one.
    
    """
    ...
    kind: Literal['PackageOf'] | Literal['GlobOf'] | Literal['NameOf'] | Literal['NoTarget']
    class PackageOf(ImportTarget):
        kind: Literal['PackageOf'] = 'PackageOf'
        def __init__(self, __p1: str, __p2: PackageRef):
            """
             for type PackageRef, see 'loupe.hir/def_map.pyi'
            """
            ...
        @readonly
        field0: str
        @readonly
        field1: PackageRef
        __match_args__ = ('field0', 'field1')
    class GlobOf(ImportTarget):
        kind: Literal['GlobOf'] = 'GlobOf'
        def __init__(self, __p1: PackageRef, __p2: str):
            """
             for type PackageRef, see 'loupe.hir/def_map.pyi'
            """
            ...
        @readonly
        field0: PackageRef
        @readonly
        field1: str
        __match_args__ = ('field0', 'field1')
    class NameOf(ImportTarget):
        kind: Literal['NameOf'] = 'NameOf'
        def __init__(self, __p1: PackageRef, __p2: str, __p3: str, __p4: str | None):
            """
             for type PackageRef, see 'loupe.hir/def_map.pyi'
            """
            ...
        @readonly
        field0: PackageRef
        @readonly
        field1: str
        @readonly
        field2: str
        @readonly
        field3: str | None
        __match_args__ = ('field0', 'field1', 'field2', 'field3')
    class NoTarget(ImportTarget):
        kind: Literal['NoTarget'] = 'NoTarget'
        def __init__(self, __p1: ImportError):
            ...
        @readonly
        field0: ImportError
        __match_args__ = ('field0')
