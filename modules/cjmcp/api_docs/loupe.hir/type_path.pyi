from typing import Literal

class TypeScope:
    """
    Where the types of a declaration's signature are looked up, rust-analyzer's `Resolver`: the type parameters of the declaration, then of the type or `extend` it is a member of, the innermost first, each shadowing anything of its name (N55); then the scope of its file.
    """
    def __init__(self, __generics: list[Generics], __pkg: Package, __file: SourceFile):
        """
         for type SourceFile, see 'loupe.db/db.pyi'
         for type Package, see 'loupe.db/project.pyi'
        """
        ...
    @property
    def generics(self) -> list[Generics]:
        """
        The type parameters of the declaration, then of its parent, if it has one.
        """
        ...
    @property
    def pkg(self) -> Package:
        """
         for type Package, see 'loupe.db/project.pyi'
        """
        ...
    @property
    def file(self) -> SourceFile:
        """
         for type SourceFile, see 'loupe.db/db.pyi'
        """
        ...
class PathResolution:
    """
    What a segment of a path in a type resolves to.
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: PathResolution) -> bool:
        ...
    def __ne__(self, __other: PathResolution) -> bool:
        ...
    kind: Literal['Resolved', 'AmbiguousPath', 'ConflictedPackages', 'UnresolvedPath']
    class Resolved(PathResolution):
        kind: Literal['Resolved'] = 'Resolved'
        def __init__(self, __p1: TypeTarget):
            ...
        @property
        def field0(self) -> TypeTarget:
            ...
        __match_args__ = ('field0')
    class AmbiguousPath(PathResolution):
        kind: Literal['AmbiguousPath'] = 'AmbiguousPath'
        def __init__(self, __p1: list[ScopeTarget]):
            """
             for type ScopeTarget, see 'loupe.hir/scope.pyi'
            """
            ...
        @property
        def field0(self) -> list[ScopeTarget]:
            ...
        __match_args__ = ('field0')
    class ConflictedPackages(PathResolution):
        kind: Literal['ConflictedPackages'] = 'ConflictedPackages'
        def __init__(self, __p1: list[PackageRef]):
            """
             for type PackageRef, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> list[PackageRef]:
            ...
        __match_args__ = ('field0')
    class UnresolvedPath(PathResolution):
        kind: Literal['UnresolvedPath'] = 'UnresolvedPath'
        def __init__(self):
            ...
class TypeTarget:
    """
    What a segment of a path in a type names.
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: TypeTarget) -> bool:
        ...
    def __ne__(self, __other: TypeTarget) -> bool:
        ...
    kind: Literal['TypeOf', 'GenericOf', 'LocalGenericOf', 'QualifierOf']
    class TypeOf(TypeTarget):
        kind: Literal['TypeOf'] = 'TypeOf'
        def __init__(self, __p1: DefId):
            """
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        __match_args__ = ('field0')
    class GenericOf(TypeTarget):
        kind: Literal['GenericOf'] = 'GenericOf'
        def __init__(self, __p1: DefId, __p2: int):
            """
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        @property
        def field1(self) -> int:
            ...
        __match_args__ = ('field0', 'field1')
    class LocalGenericOf(TypeTarget):
        kind: Literal['LocalGenericOf'] = 'LocalGenericOf'
        def __init__(self, __p1: DefId, __p2: int, __p3: int):
            """
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        @property
        def field1(self) -> int:
            ...
        @property
        def field2(self) -> int:
            ...
        __match_args__ = ('field0', 'field1', 'field2')
    class QualifierOf(TypeTarget):
        kind: Literal['QualifierOf'] = 'QualifierOf'
        def __init__(self, __p1: PackageRef):
            """
             for type PackageRef, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> PackageRef:
            ...
        __match_args__ = ('field0')
class Generics:
    """
    The type parameters of one declaration: the declaration, which `GenericOf` names, and their names in order, an index among them a `GenericOf`'s.
    """
    def __init__(self, __owner: DefId, __names: list[str]):
        """
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def owner(self) -> DefId:
        """
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def names(self) -> list[str]:
        ...
