class SemanticType:
    """
    
    A resolved type bound to the same snapshot as its semantic object. Used from one thread
    at a time; operations throw CancelledException after an input write or request cancellation.
    Nested types retain this context without creating another snapshot or exposing interned ids.
    
    """
    def kind(self) -> SemanticTypeKind:
        """
        
        Structure with aliases resolved; related definitions and child types need no database argument.
        Invalid, unsupported and unavailable types retain their distinct meanings and reasons.
        
        """
        ...
    def display(self) -> str:
        """
        
        Type display read from this revision; unknown/error details remain available through kind().
        
        """
        ...
class SemanticTypeKind:
    """
    
    Resolved type structure. Child types and definitions share the originating snapshot;
    copied names, sizes and reasons remain descriptions of that revision after cancellation.
    FunctionType carries parameter types, return type and whether it uses the C calling convention.
    FixedArrayType carries its element type and length. TypeParameterType names the binder's parameter.
    
    """
    ...
    kind: Literal['PrimitiveType'] | Literal['DeclaredType'] | Literal['CompilerOwnedType'] | Literal['TupleType'] | Literal['FunctionType'] | Literal['FixedArrayType'] | Literal['TypeParameterType'] | Literal['SelfType'] | Literal['InvalidType'] | Literal['UnsupportedType'] | Literal['UnavailableType'] | Literal['InferenceVariableType']
    class PrimitiveType(SemanticTypeKind):
        kind: Literal['PrimitiveType'] = 'PrimitiveType'
        def __init__(self, __p1: str):
            ...
        @readonly
        field0: str
        __match_args__ = ('field0')
    class DeclaredType(SemanticTypeKind):
        kind: Literal['DeclaredType'] = 'DeclaredType'
        def __init__(self, __p1: SemanticObject, __p2: list[SemanticType]):
            """
             for type SemanticObject, see 'loupe/semantic.pyi'
            """
            ...
        @readonly
        field0: SemanticObject
        @readonly
        field1: list[SemanticType]
        __match_args__ = ('field0', 'field1')
    class CompilerOwnedType(SemanticTypeKind):
        kind: Literal['CompilerOwnedType'] = 'CompilerOwnedType'
        def __init__(self, __p1: CompilerType, __p2: list[SemanticType]):
            """
             for type CompilerType, see 'loupe.hir/compiler_types.pyi'
            """
            ...
        @readonly
        field0: CompilerType
        @readonly
        field1: list[SemanticType]
        __match_args__ = ('field0', 'field1')
    class TupleType(SemanticTypeKind):
        kind: Literal['TupleType'] = 'TupleType'
        def __init__(self, __p1: list[SemanticType]):
            ...
        @readonly
        field0: list[SemanticType]
        __match_args__ = ('field0')
    class FunctionType(SemanticTypeKind):
        kind: Literal['FunctionType'] = 'FunctionType'
        def __init__(self, __p1: list[SemanticType], __p2: SemanticType, __p3: bool):
            ...
        @readonly
        field0: list[SemanticType]
        @readonly
        field1: SemanticType
        @readonly
        field2: bool
        __match_args__ = ('field0', 'field1', 'field2')
    class FixedArrayType(SemanticTypeKind):
        kind: Literal['FixedArrayType'] = 'FixedArrayType'
        def __init__(self, __p1: SemanticType, __p2: int):
            ...
        @readonly
        field0: SemanticType
        @readonly
        field1: int
        __match_args__ = ('field0', 'field1')
    class TypeParameterType(SemanticTypeKind):
        kind: Literal['TypeParameterType'] = 'TypeParameterType'
        def __init__(self, __p1: SemanticObject):
            """
             for type SemanticObject, see 'loupe/semantic.pyi'
            """
            ...
        @readonly
        field0: SemanticObject
        __match_args__ = ('field0')
    class SelfType(SemanticTypeKind):
        kind: Literal['SelfType'] = 'SelfType'
        def __init__(self):
            ...
    class InvalidType(SemanticTypeKind):
        kind: Literal['InvalidType'] = 'InvalidType'
        def __init__(self):
            ...
    class UnsupportedType(SemanticTypeKind):
        kind: Literal['UnsupportedType'] = 'UnsupportedType'
        def __init__(self, __p1: Todo):
            """
             for type Todo, see 'loupe.hir/ty.pyi'
            """
            ...
        @readonly
        field0: Todo
        __match_args__ = ('field0')
    class UnavailableType(SemanticTypeKind):
        kind: Literal['UnavailableType'] = 'UnavailableType'
        def __init__(self, __p1: UnknownReason):
            """
             for type UnknownReason, see 'loupe.hir/ty.pyi'
            """
            ...
        @readonly
        field0: UnknownReason
        __match_args__ = ('field0')
    class InferenceVariableType(SemanticTypeKind):
        kind: Literal['InferenceVariableType'] = 'InferenceVariableType'
        def __init__(self):
            ...
