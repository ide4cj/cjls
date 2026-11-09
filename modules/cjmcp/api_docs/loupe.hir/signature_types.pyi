class SignatureTypes:
    def __init__(self, *, generics: list[str] = ..., params: list[Ty] = ..., paramNames: list[str | None] = ..., paramDefaults: list[bool] = ..., isCVariadic: bool = ..., ty: Ty | None = ..., supers: list[Ty] = ..., bounds: list[TyBound] = ..., errors: list[TyError] = ..., typePaths: list[TypePathTarget] = ...):
        """
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def generics(self) -> list[str]:
        ...
    @property
    def params(self) -> list[Ty]:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def paramNames(self) -> list[str | None]:
        ...
    @property
    def paramDefaults(self) -> list[bool]:
        ...
    @property
    def isCVariadic(self) -> bool:
        ...
    @property
    def ty(self) -> Ty | None:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def supers(self) -> list[Ty]:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def bounds(self) -> list[TyBound]:
        ...
    @property
    def errors(self) -> list[TyError]:
        ...
    @property
    def typePaths(self) -> list[TypePathTarget]:
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
class TyErrorKind:
    """
    
    Why a type of a signature is an error, as cjc says it.
    
    """
    def __eq__(self, __other: TyErrorKind) -> bool:
        ...
    def __ne__(self, __other: TyErrorKind) -> bool:
        ...
    kind: Literal['UndeclaredType'] | Literal['NotAType'] | Literal['NeedsTypeArgs'] | Literal['WrongTypeArgCount'] | Literal['ThisNotAllowed'] | Literal['TypeCycle']
    class UndeclaredType(TyErrorKind):
        kind: Literal['UndeclaredType'] = 'UndeclaredType'
        def __init__(self, __p1: str):
            ...
        @readonly
        field0: str
        __match_args__ = ('field0')
    class NotAType(TyErrorKind):
        kind: Literal['NotAType'] = 'NotAType'
        def __init__(self, __p1: str):
            ...
        @readonly
        field0: str
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
        @readonly
        field0: bool
        __match_args__ = ('field0')
    class TypeCycle(TyErrorKind):
        kind: Literal['TypeCycle'] = 'TypeCycle'
        def __init__(self, __p1: list[str]):
            ...
        @readonly
        field0: list[str]
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
        ...
    def __eq__(self, __other: TyError) -> bool:
        ...
    def __ne__(self, __other: TyError) -> bool:
        ...
class TypePathTarget:
    """
    
    What each segment of the path of a type names, as lowering it resolved it: what highlighting and go to definition
    read, not resolving it again.
    
    
    A declaration's signature as types (D54): what `Signature` writes, each `TypeRef` lowered to a
    `Ty`, or what a `.cjo` resolved. One query of each declaration, as `signature` is.
    
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
        ...
    def __eq__(self, __other: TypePathTarget) -> bool:
        ...
    def __ne__(self, __other: TypePathTarget) -> bool:
        ...
