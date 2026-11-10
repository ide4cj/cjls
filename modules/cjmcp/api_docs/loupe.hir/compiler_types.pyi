from typing import Literal

class CompilerType:
    """

    Compiler-owned type heads; declaration identities only provide scoped names and navigation.

    """
    def __eq__(self, __other: CompilerType) -> bool:
        ...
    def __ne__(self, __other: CompilerType) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    def __repr__(self) -> str:
        ...
    kind: Literal['PointerType', 'CStringType', 'RawArrayType', 'CFuncType', 'VArrayType']
    class PointerType(CompilerType):
        kind: Literal['PointerType'] = 'PointerType'
        def __init__(self):
            ...
    class CStringType(CompilerType):
        kind: Literal['CStringType'] = 'CStringType'
        def __init__(self):
            ...
    class RawArrayType(CompilerType):
        kind: Literal['RawArrayType'] = 'RawArrayType'
        def __init__(self):
            ...
    class CFuncType(CompilerType):
        kind: Literal['CFuncType'] = 'CFuncType'
        def __init__(self):
            ...
    class VArrayType(CompilerType):
        kind: Literal['VArrayType'] = 'VArrayType'
        def __init__(self):
            ...
