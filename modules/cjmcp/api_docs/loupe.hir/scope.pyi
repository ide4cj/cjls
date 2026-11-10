from typing import Literal

class Resolution:
    """

    What a name means in a file's scope.

    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: Resolution) -> bool:
        ...
    def __ne__(self, __other: Resolution) -> bool:
        ...
    kind: Literal['Found', 'FoundPackage', 'Ambiguous', 'Ctors', 'NotFound']
    class Found(Resolution):
        kind: Literal['Found'] = 'Found'
        def __init__(self, __p1: list[DefId]):
            """
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> list[DefId]:
            ...
        __match_args__ = ('field0')
    class FoundPackage(Resolution):
        kind: Literal['FoundPackage'] = 'FoundPackage'
        def __init__(self, __p1: PackageRef):
            """
             for type PackageRef, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> PackageRef:
            ...
        __match_args__ = ('field0')
    class Ambiguous(Resolution):
        kind: Literal['Ambiguous'] = 'Ambiguous'
        def __init__(self, __p1: list[ScopeTarget]):
            ...
        @property
        def field0(self) -> list[ScopeTarget]:
            ...
        __match_args__ = ('field0')
    class Ctors(Resolution):
        kind: Literal['Ctors'] = 'Ctors'
        def __init__(self, __p1: list[DefId], __p2: list[DefId]):
            """
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> list[DefId]:
            ...
        @property
        def field1(self) -> list[DefId]:
            ...
        __match_args__ = ('field0', 'field1')
    class NotFound(Resolution):
        kind: Literal['NotFound'] = 'NotFound'
        def __init__(self):
            ...
class Namespace:
    """

    Where a name is used: as a type, or as a value (N41), or as the macro of a call. A type does not
    see functions or variables; neither sees a macro, nor a macro anything else (a function `Derive`
    leaves `@Derive` the imported macro).

    """
    def __eq__(self, __other: Namespace) -> bool:
        ...
    def __ne__(self, __other: Namespace) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    kind: Literal['Types', 'Values', 'Macros']
    class Types(Namespace):
        kind: Literal['Types'] = 'Types'
        def __init__(self):
            ...
    class Values(Namespace):
        kind: Literal['Values'] = 'Values'
        def __init__(self):
            ...
    class Macros(Namespace):
        kind: Literal['Macros'] = 'Macros'
        def __init__(self):
            ...
class ScopeTarget:
    """

    What a name of a scope stands for: a declaration, or a package imported by its name (N7, N43).

    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: ScopeTarget) -> bool:
        ...
    def __ne__(self, __other: ScopeTarget) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    kind: Literal['OfDecl', 'OfPackage']
    class OfDecl(ScopeTarget):
        kind: Literal['OfDecl'] = 'OfDecl'
        def __init__(self, __p1: DefId):
            """
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        __match_args__ = ('field0')
    class OfPackage(ScopeTarget):
        kind: Literal['OfPackage'] = 'OfPackage'
        def __init__(self, __p1: PackageRef):
            """
             for type PackageRef, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> PackageRef:
            ...
        __match_args__ = ('field0')
class ImportSite:
    """

    The path of an import a name came by: its file, its import, the path's index in it, and the
    visibility it re-exports with.

    """
    def __init__(self, __file: ItemFile, __item: ItemId, __path: int, __level: Visibility):
        """
         for type Visibility, see 'loupe.hir/def_map.pyi'
         for type ItemId, see 'loupe.hir/item_id.pyi'
         for type ItemFile, see 'loupe.hir/binary.pyi'
        """
        ...
    @property
    def file(self) -> ItemFile:
        """
         for type ItemFile, see 'loupe.hir/binary.pyi'
        """
        ...
    @property
    def item(self) -> ItemId:
        """
         for type ItemId, see 'loupe.hir/item_id.pyi'
        """
        ...
    @property
    def path(self) -> int:
        ...
    @property
    def level(self) -> Visibility:
        """
         for type Visibility, see 'loupe.hir/def_map.pyi'
        """
        ...
    def __eq__(self, __other: ImportSite) -> bool:
        ...
    def __ne__(self, __other: ImportSite) -> bool:
        ...
class Imported:
    """

    A name an import brings, and the path it came by; `None` for the prelude.

    """
    def __init__(self, __target: ScopeTarget, __site: ImportSite | None):
        ...
    @property
    def target(self) -> ScopeTarget:
        ...
    @property
    def site(self) -> ImportSite | None:
        ...
    def __eq__(self, __other: Imported) -> bool:
        ...
    def __ne__(self, __other: Imported) -> bool:
        ...
class Glob:
    """

    An import of every name of a package, kept as the package: its names are read at a lookup.

    """
    def __init__(self, __pkg: PackageRef, __relation: PackageRelation, __level: Visibility, __site: ImportSite | None):
        """
         for type Visibility, see 'loupe.hir/def_map.pyi'
         for type PackageRelation, see 'loupe.hir/imports.pyi'
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
    def relation(self) -> PackageRelation:
        """

        How the importer stands to it, for what it sees (N2–N4).

         for type PackageRelation, see 'loupe.hir/imports.pyi'
        """
        ...
    @property
    def level(self) -> Visibility:
        """
         for type Visibility, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def site(self) -> ImportSite | None:
        ...
    def __eq__(self, __other: Glob) -> bool:
        ...
    def __ne__(self, __other: Glob) -> bool:
        ...
