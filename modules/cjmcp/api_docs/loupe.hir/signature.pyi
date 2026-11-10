from typing import Literal

class Signature:
    """
    The types a declaration's signature writes, nothing of its body: rust-analyzer's signatures, a query of each declaration apart from the item tree (D48), so that an edit to a type runs again what read this declaration's, not the package's names.
    """
    def __init__(self, *, generics: list[str] = ..., types: list[TypeRef] = ..., params: list[TypeRefId] = ..., paramNames: list[str | None] = ..., paramDefaults: list[bool] = ..., isCVariadic: bool = ..., ty: TypeRefId | None = ..., supers: list[TypeRefId] = ..., bounds: list[TypeBound] = ...):
        ...
    @property
    def generics(self) -> list[str]:
        """
        Its type parameters by name, in order.
        """
        ...
    @property
    def types(self) -> list[TypeRef]:
        """
        Every type it writes, one inside another before it.
        """
        ...
    @property
    def params(self) -> list[TypeRefId]:
        """
        Those of its parameters, of every list in order; an enum constructor's.
        """
        ...
    @property
    def paramNames(self) -> list[str | None]:
        """
        The name each of its parameters is passed by, `None` for one passed by place (`value!` is `value`); as many as `params`, or none if none is named.
        """
        ...
    @property
    def paramDefaults(self) -> list[bool]:
        """
        Whether each of its parameters has a default value; as many as `paramNames`.
        """
        ...
    @property
    def isCVariadic(self) -> bool:
        """
        Whether, a `foreign` function's, it takes any number of arguments more after its parameters: its `...`, none of `params`.
        """
        ...
    @property
    def ty(self) -> TypeRefId | None:
        """
        Its declared type: a function's return type, a variable's or property's type, what an alias names, the type an `extend` extends.
        """
        ...
    @property
    def supers(self) -> list[TypeRefId]:
        """
        The types after `<:`: a type's supertypes, an `extend`'s interfaces.
        """
        ...
    @property
    def bounds(self) -> list[TypeBound]:
        """
        Its `where`.
        """
        ...
    def __getitem__(self, __id: TypeRefId) -> TypeRef:
        ...
    def text(self, __id: TypeRefId) -> str:
        """
        `id` as written, but for whitespace and parameter names: `a.C<?Int64>`, `(Int64) -> Unit`.
        """
        ...
    def __eq__(self, __other: Signature) -> bool:
        ...
    def __ne__(self, __other: Signature) -> bool:
        ...
class TypeRef:
    """
    A type as a signature writes it, its names not resolved yet: rust-analyzer's `TypeRef`. What it holds are other types of the same signature; a type in parentheses is the type in them.
    """
    def __eq__(self, __other: TypeRef) -> bool:
        ...
    def __ne__(self, __other: TypeRef) -> bool:
        ...
    kind: Literal['PathRef', 'PrimRef', 'TupleRef', 'FuncRef', 'OptionRef', 'ThisRef', 'VArrayRef', 'MissingRef']
    class PathRef(TypeRef):
        kind: Literal['PathRef'] = 'PathRef'
        def __init__(self, __p1: list[TypeSegment]):
            ...
        @property
        def field0(self) -> list[TypeSegment]:
            ...
        __match_args__ = ('field0')
    class PrimRef(TypeRef):
        kind: Literal['PrimRef'] = 'PrimRef'
        def __init__(self, __p1: str):
            ...
        @property
        def field0(self) -> str:
            ...
        __match_args__ = ('field0')
    class TupleRef(TypeRef):
        kind: Literal['TupleRef'] = 'TupleRef'
        def __init__(self, __p1: list[TypeRefId]):
            ...
        @property
        def field0(self) -> list[TypeRefId]:
            ...
        __match_args__ = ('field0')
    class FuncRef(TypeRef):
        kind: Literal['FuncRef'] = 'FuncRef'
        def __init__(self, __p1: list[TypeRefId], __p2: TypeRefId):
            ...
        @property
        def field0(self) -> list[TypeRefId]:
            ...
        @property
        def field1(self) -> TypeRefId:
            ...
        __match_args__ = ('field0', 'field1')
    class OptionRef(TypeRef):
        kind: Literal['OptionRef'] = 'OptionRef'
        def __init__(self, __p1: TypeRefId):
            ...
        @property
        def field0(self) -> TypeRefId:
            ...
        __match_args__ = ('field0')
    class ThisRef(TypeRef):
        kind: Literal['ThisRef'] = 'ThisRef'
        def __init__(self):
            ...
    class VArrayRef(TypeRef):
        kind: Literal['VArrayRef'] = 'VArrayRef'
        def __init__(self, __p1: TypeRefId, __p2: str | None):
            ...
        @property
        def field0(self) -> TypeRefId:
            ...
        @property
        def field1(self) -> str | None:
            ...
        __match_args__ = ('field0', 'field1')
    class MissingRef(TypeRef):
        kind: Literal['MissingRef'] = 'MissingRef'
        def __init__(self):
            ...
class TypeSegment:
    """
    A segment of a path in a type, `C<T>` of `a.C<T>`: its name and its type arguments.
    """
    def __init__(self, __name: str, __args: list[TypeRefId]):
        ...
    @property
    def name(self) -> str:
        ...
    @property
    def args(self) -> list[TypeRefId]:
        ...
    def __eq__(self, __other: TypeSegment) -> bool:
        ...
    def __ne__(self, __other: TypeSegment) -> bool:
        ...
class TypeRefId:
    """
    A type of a signature, by its place among the signature's `types`.
    """
    def __init__(self, __index: int):
        ...
    @property
    def index(self) -> int:
        ...
    def __eq__(self, __other: TypeRefId) -> bool:
        ...
    def __ne__(self, __other: TypeRefId) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    def __repr__(self) -> str:
        ...
class TypeBound:
    """
    A type and its bounds, `T <: A & B` of a `where`.
    """
    def __init__(self, __ty: TypeRefId, __bounds: list[TypeRefId]):
        ...
    @property
    def ty(self) -> TypeRefId:
        ...
    @property
    def bounds(self) -> list[TypeRefId]:
        ...
    def __eq__(self, __other: TypeBound) -> bool:
        ...
    def __ne__(self, __other: TypeBound) -> bool:
        ...
