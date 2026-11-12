from typing import Literal

class Ty:
    """
    A type as inference takes it, rust-analyzer's `Ty`: its names resolved, its aliases expanded, `?T` an `Option<T>`. Interned (D54), as R1's and cjc's are (`TypeManager` hands out one `Ty` for one declaration and arguments): two equal types are one id, compared and hashed as a number.
    """
    ...
class GenericOwner:
    """
    A generic binder: a declaration, or a local function within its owner's body (D50). Local function indices are body-local, so the enclosing declaration is part of identity.
    """
    def __eq__(self, __other: GenericOwner) -> bool:
        ...
    def __ne__(self, __other: GenericOwner) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    kind: Literal['Declaration', 'LocalFunction']
    class Declaration(GenericOwner):
        kind: Literal['Declaration'] = 'Declaration'
        def __init__(self, __p1: DefId):
            """
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        __match_args__ = ('field0',)
    class LocalFunction(GenericOwner):
        kind: Literal['LocalFunction'] = 'LocalFunction'
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
class TyKind:
    """
    What a `Ty` is: resolved signature types, unknown types and call-local inference variables.
    """
    def __hash__(self) -> int:
        """
        by hand: `@Derive[Hashable]` hashes each field, and std's `Array` is not `Hashable`
        """
        ...
    def __eq__(self, __other: TyKind) -> bool:
        ...
    def __ne__(self, __other: TyKind) -> bool:
        ...
    kind: Literal['PrimTy', 'DeclTy', 'BuiltInTy', 'TupleTy', 'FuncTy', 'VArrayTy', 'ParamTy', 'ThisTy', 'ErrorTy', 'TodoTy', 'UnknownTy', 'InferTy']
    class PrimTy(TyKind):
        kind: Literal['PrimTy'] = 'PrimTy'
        def __init__(self, __p1: str):
            ...
        @property
        def field0(self) -> str:
            ...
        __match_args__ = ('field0',)
    class DeclTy(TyKind):
        kind: Literal['DeclTy'] = 'DeclTy'
        def __init__(self, __p1: DefId, __p2: list[Ty]):
            """
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        @property
        def field1(self) -> list[Ty]:
            ...
        __match_args__ = ('field0', 'field1')
    class BuiltInTy(TyKind):
        kind: Literal['BuiltInTy'] = 'BuiltInTy'
        def __init__(self, __p1: CompilerType, __p2: list[Ty]):
            """
             for type CompilerType, see 'loupe.hir/compiler_types.pyi'
            """
            ...
        @property
        def field0(self) -> CompilerType:
            ...
        @property
        def field1(self) -> list[Ty]:
            ...
        __match_args__ = ('field0', 'field1')
    class TupleTy(TyKind):
        kind: Literal['TupleTy'] = 'TupleTy'
        def __init__(self, __p1: list[Ty]):
            ...
        @property
        def field0(self) -> list[Ty]:
            ...
        __match_args__ = ('field0',)
    class FuncTy(TyKind):
        kind: Literal['FuncTy'] = 'FuncTy'
        def __init__(self, __p1: list[Ty], __p2: Ty, __p3: bool):
            ...
        @property
        def field0(self) -> list[Ty]:
            ...
        @property
        def field1(self) -> Ty:
            ...
        @property
        def field2(self) -> bool:
            ...
        __match_args__ = ('field0', 'field1', 'field2')
    class VArrayTy(TyKind):
        kind: Literal['VArrayTy'] = 'VArrayTy'
        def __init__(self, __p1: Ty, __p2: int):
            ...
        @property
        def field0(self) -> Ty:
            ...
        @property
        def field1(self) -> int:
            ...
        __match_args__ = ('field0', 'field1')
    class ParamTy(TyKind):
        kind: Literal['ParamTy'] = 'ParamTy'
        def __init__(self, __p1: GenericOwner, __p2: int):
            ...
        @property
        def field0(self) -> GenericOwner:
            ...
        @property
        def field1(self) -> int:
            ...
        __match_args__ = ('field0', 'field1')
    class ThisTy(TyKind):
        kind: Literal['ThisTy'] = 'ThisTy'
        def __init__(self):
            ...
    class ErrorTy(TyKind):
        kind: Literal['ErrorTy'] = 'ErrorTy'
        def __init__(self):
            ...
    class TodoTy(TyKind):
        kind: Literal['TodoTy'] = 'TodoTy'
        def __init__(self, __p1: Todo):
            ...
        @property
        def field0(self) -> Todo:
            ...
        __match_args__ = ('field0',)
    class UnknownTy(TyKind):
        kind: Literal['UnknownTy'] = 'UnknownTy'
        def __init__(self, __p1: UnknownReason):
            ...
        @property
        def field0(self) -> UnknownReason:
            ...
        __match_args__ = ('field0',)
    class InferTy(TyKind):
        kind: Literal['InferTy'] = 'InferTy'
        def __init__(self, __p1: int):
            ...
        @property
        def field0(self) -> int:
            ...
        __match_args__ = ('field0',)
class Todo:
    """
    Why the analysis cannot find a type (D77): what it does not do yet, each a gap of its own.
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: Todo) -> bool:
        ...
    def __ne__(self, __other: Todo) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    kind: Literal['MacroCall', 'MacroMember']
    class MacroCall(Todo):
        kind: Literal['MacroCall'] = 'MacroCall'
        def __init__(self):
            ...
    class MacroMember(Todo):
        kind: Literal['MacroMember'] = 'MacroMember'
        def __init__(self):
            ...
class UnknownReason:
    """
    Why a type is unknown given the available inputs, inference progress and resources.
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: UnknownReason) -> bool:
        ...
    def __ne__(self, __other: UnknownReason) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    kind: Literal['BinaryType', 'NotInferred', 'NoStd', 'GenericBoundsLimit', 'LambdaCandidatesLimit']
    class BinaryType(UnknownReason):
        kind: Literal['BinaryType'] = 'BinaryType'
        def __init__(self):
            ...
    class NotInferred(UnknownReason):
        kind: Literal['NotInferred'] = 'NotInferred'
        def __init__(self):
            ...
    class NoStd(UnknownReason):
        kind: Literal['NoStd'] = 'NoStd'
        def __init__(self):
            ...
    class GenericBoundsLimit(UnknownReason):
        kind: Literal['GenericBoundsLimit'] = 'GenericBoundsLimit'
        def __init__(self):
            ...
    class LambdaCandidatesLimit(UnknownReason):
        kind: Literal['LambdaCandidatesLimit'] = 'LambdaCandidatesLimit'
        def __init__(self):
            ...
