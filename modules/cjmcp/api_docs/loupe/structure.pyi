from typing import Literal

class StructureKind:
    """
    The declaration category of a source structure node.
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: StructureKind) -> bool:
        ...
    def __ne__(self, __other: StructureKind) -> bool:
        ...
    kind: Literal['Class', 'Interface', 'Struct', 'Enum', 'EnumConstructor', 'Extension', 'Function', 'Method', 'Macro', 'Main', 'Constructor', 'Finalizer', 'Property', 'Variable', 'Field', 'Constant', 'TypeAlias']
    class Class(StructureKind):
        kind: Literal['Class'] = 'Class'
        def __init__(self):
            ...
    class Interface(StructureKind):
        kind: Literal['Interface'] = 'Interface'
        def __init__(self):
            ...
    class Struct(StructureKind):
        kind: Literal['Struct'] = 'Struct'
        def __init__(self):
            ...
    class Enum(StructureKind):
        kind: Literal['Enum'] = 'Enum'
        def __init__(self):
            ...
    class EnumConstructor(StructureKind):
        kind: Literal['EnumConstructor'] = 'EnumConstructor'
        def __init__(self):
            ...
    class Extension(StructureKind):
        kind: Literal['Extension'] = 'Extension'
        def __init__(self):
            ...
    class Function(StructureKind):
        kind: Literal['Function'] = 'Function'
        def __init__(self):
            ...
    class Method(StructureKind):
        kind: Literal['Method'] = 'Method'
        def __init__(self):
            ...
    class Macro(StructureKind):
        kind: Literal['Macro'] = 'Macro'
        def __init__(self):
            ...
    class Main(StructureKind):
        kind: Literal['Main'] = 'Main'
        def __init__(self):
            ...
    class Constructor(StructureKind):
        kind: Literal['Constructor'] = 'Constructor'
        def __init__(self):
            ...
    class Finalizer(StructureKind):
        kind: Literal['Finalizer'] = 'Finalizer'
        def __init__(self):
            ...
    class Property(StructureKind):
        kind: Literal['Property'] = 'Property'
        def __init__(self):
            ...
    class Variable(StructureKind):
        kind: Literal['Variable'] = 'Variable'
        def __init__(self):
            ...
    class Field(StructureKind):
        kind: Literal['Field'] = 'Field'
        def __init__(self):
            ...
    class Constant(StructureKind):
        kind: Literal['Constant'] = 'Constant'
        def __init__(self):
            ...
    class TypeAlias(StructureKind):
        kind: Literal['TypeAlias'] = 'TypeAlias'
        def __init__(self):
            ...
class StructureNode:
    """
    One declaration of a file's outline. `range` is the whole of it, doc comment included; `selectionRange`, inside it, is its name.
    """
    def __init__(self, __name: str, __kind: StructureKind, __range: TextRange, __selectionRange: TextRange, __children: list[StructureNode]):
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def name(self) -> str:
        ...
    @property
    def kind(self) -> StructureKind:
        ...
    @property
    def range(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def selectionRange(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def children(self) -> list[StructureNode]:
        ...
