from typing import Literal

class SignatureTypes:
    """

    A declaration's signature as types (D54): what `Signature` writes, each `TypeRef` lowered to a
    `Ty`, or what a `.cjo` resolved. One query of each declaration, as `signature` is.

    """
    def __init__(self, *, generics: list[str] = ..., params: list[Ty] = ..., paramNames: list[str | None] = ..., paramDefaults: list[bool] = ..., isCVariadic: bool = ..., ty: Ty | None = ..., supers: list[Ty] = ..., bounds: list[TyBound] = ..., errors: list[TyError] = ..., typePaths: list[TypePathTarget] = ...):
        """
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def generics(self) -> list[str]:
        """

        Its type parameters by name, in order: a `ParamTy` of it is by its place among them.

        """
        ...
    @property
    def params(self) -> list[Ty]:
        """

        Those of its parameters, of every list in order; an enum constructor's.

         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def paramNames(self) -> list[str | None]:
        """

        The name each of its parameters is passed by, `None` for one passed by place; as many as
        `params`, or none if none is named.

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

        Whether, a `foreign` function's, it takes any number of arguments more after `params`:
        its `...`; of a source.

        """
        ...
    @property
    def ty(self) -> Ty | None:
        """

        What a declaration is a value or a type of: a function's return type, a variable's or
        property's type, the type an `extend` extends, what an alias expands to; a type's own,
        its parameters its arguments (`C<T>`); a constructor's, an `init`'s or an enum
        constructor's, its type's. `None` where it is not written: inference's.

         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def supers(self) -> list[Ty]:
        """

        The types after `<:`: a type's supertypes, an `extend`'s interfaces; a class's superclass
        first, `Object` if it names none, as cjc adds it.

         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def bounds(self) -> list[TyBound]:
        """

        Its `where`, as written: not the bounds cjc adds to an `extend` of a generic type.

        """
        ...
    @property
    def errors(self) -> list[TyError]:
        """

        The types of its source that are errors; none of a `.cjo`, which cjc checked.

        """
        ...
    @property
    def typePaths(self) -> list[TypePathTarget]:
        """

        What each segment of each path of its types names, by the type; none of a `.cjo`.

        """
        ...
    def pathOf(self, __ty: TypeRefId) -> list[PathResolution] | None:
        """

        What each segment of the path of the type `ty` of the signature names, if it is one.

         for type PathResolution, see 'loupe.hir/type_path.pyi'
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    def __eq__(self, __other: SignatureTypes) -> bool:
        ...
    def __ne__(self, __other: SignatureTypes) -> bool:
        ...
class TyErrorKind:
    """

    Why a type of a signature is an error, as cjc says it.

    """
    def __eq__(self, __other: TyErrorKind) -> bool:
        ...
    def __ne__(self, __other: TyErrorKind) -> bool:
        ...
    kind: Literal['UndeclaredType', 'NotAType', 'NeedsTypeArgs', 'WrongTypeArgCount', 'ThisNotAllowed', 'TypeCycle']
    class UndeclaredType(TyErrorKind):
        kind: Literal['UndeclaredType'] = 'UndeclaredType'
        def __init__(self, __p1: str):
            ...
        @property
        def field0(self) -> str:
            ...
        __match_args__ = ('field0')
    class NotAType(TyErrorKind):
        kind: Literal['NotAType'] = 'NotAType'
        def __init__(self, __p1: str):
            ...
        @property
        def field0(self) -> str:
            ...
        __match_args__ = ('field0')
    class NeedsTypeArgs(TyErrorKind):
        kind: Literal['NeedsTypeArgs'] = 'NeedsTypeArgs'
        def __init__(self):
            ...
    class WrongTypeArgCount(TyErrorKind):
        kind: Literal['WrongTypeArgCount'] = 'WrongTypeArgCount'
        def __init__(self):
            ...
    class ThisNotAllowed(TyErrorKind):
        kind: Literal['ThisNotAllowed'] = 'ThisNotAllowed'
        def __init__(self, __p1: bool):
            ...
        @property
        def field0(self) -> bool:
            ...
        __match_args__ = ('field0')
    class TypeCycle(TyErrorKind):
        kind: Literal['TypeCycle'] = 'TypeCycle'
        def __init__(self, __p1: list[str]):
            ...
        @property
        def field0(self) -> list[str]:
            ...
        __match_args__ = ('field0')
class TyError:
    """

    A type of a signature that is an error: the type, by its id in the signature, and why.

    """
    def __init__(self, __at: TypeRefId, __kind: TyErrorKind):
        """
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def at(self) -> TypeRefId:
        """
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def kind(self) -> TyErrorKind:
        ...
    def message(self) -> str:
        """
        Return the diagnostic text for this signature type error.
        """
        ...
    def __eq__(self, __other: TyError) -> bool:
        ...
    def __ne__(self, __other: TyError) -> bool:
        ...
class TyBound:
    """

    A type and its bounds, `T <: A & B` of a `where`, as types.

    """
    def __init__(self, __ty: Ty, __bounds: list[Ty]):
        """
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def ty(self) -> Ty:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def bounds(self) -> list[Ty]:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    def __eq__(self, __other: TyBound) -> bool:
        ...
    def __ne__(self, __other: TyBound) -> bool:
        ...
class TypePathTarget:
    """

    What each segment of the path of a type names, as lowering it resolved it: what highlighting and go to definition
    read, not resolving it again.

    """
    def __init__(self, __ty: TypeRefId, __resolution: list[PathResolution]):
        """
         for type PathResolution, see 'loupe.hir/type_path.pyi'
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def ty(self) -> TypeRefId:
        """
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def resolution(self) -> list[PathResolution]:
        """
         for type PathResolution, see 'loupe.hir/type_path.pyi'
        """
        ...
    def keyIndex(self) -> int:
        """
        The signature type-reference index associated with this path resolution.
        """
        ...
    def __eq__(self, __other: TypePathTarget) -> bool:
        ...
    def __ne__(self, __other: TypePathTarget) -> bool:
        ...
