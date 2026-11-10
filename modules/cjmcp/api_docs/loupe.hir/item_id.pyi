from typing import Literal

class ItemKind:
    """

    What an item is: a declaration the item tree holds, an import, or a macro call on no declaration;
    `BuiltIn` gives a compiler-owned type a scoped name, from std.core's binary or synthetic source
    declarations; its semantic type does not depend on this identity (D154).

    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: ItemKind) -> bool:
        ...
    def __ne__(self, __other: ItemKind) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    kind: Literal['Import', 'Func', 'Main', 'Macro', 'Class', 'Interface', 'Struct', 'Enum', 'Extend', 'TypeAlias', 'Var', 'Prop', 'Init', 'Finalizer', 'PrimaryInit', 'EnumCtor', 'MacroCall', 'BuiltIn']
    class Import(ItemKind):
        kind: Literal['Import'] = 'Import'
        def __init__(self):
            ...
    class Func(ItemKind):
        kind: Literal['Func'] = 'Func'
        def __init__(self):
            ...
    class Main(ItemKind):
        kind: Literal['Main'] = 'Main'
        def __init__(self):
            ...
    class Macro(ItemKind):
        kind: Literal['Macro'] = 'Macro'
        def __init__(self):
            ...
    class Class(ItemKind):
        kind: Literal['Class'] = 'Class'
        def __init__(self):
            ...
    class Interface(ItemKind):
        kind: Literal['Interface'] = 'Interface'
        def __init__(self):
            ...
    class Struct(ItemKind):
        kind: Literal['Struct'] = 'Struct'
        def __init__(self):
            ...
    class Enum(ItemKind):
        kind: Literal['Enum'] = 'Enum'
        def __init__(self):
            ...
    class Extend(ItemKind):
        kind: Literal['Extend'] = 'Extend'
        def __init__(self):
            ...
    class TypeAlias(ItemKind):
        kind: Literal['TypeAlias'] = 'TypeAlias'
        def __init__(self):
            ...
    class Var(ItemKind):
        kind: Literal['Var'] = 'Var'
        def __init__(self):
            ...
    class Prop(ItemKind):
        kind: Literal['Prop'] = 'Prop'
        def __init__(self):
            ...
    class Init(ItemKind):
        kind: Literal['Init'] = 'Init'
        def __init__(self):
            ...
    class Finalizer(ItemKind):
        kind: Literal['Finalizer'] = 'Finalizer'
        def __init__(self):
            ...
    class PrimaryInit(ItemKind):
        kind: Literal['PrimaryInit'] = 'PrimaryInit'
        def __init__(self):
            ...
    class EnumCtor(ItemKind):
        kind: Literal['EnumCtor'] = 'EnumCtor'
        def __init__(self):
            ...
    class MacroCall(ItemKind):
        kind: Literal['MacroCall'] = 'MacroCall'
        def __init__(self):
            ...
    class BuiltIn(ItemKind):
        kind: Literal['BuiltIn'] = 'BuiltIn'
        def __init__(self):
            ...
class ItemId:
    """

    An item of a file, named so that an edit elsewhere leaves it as it is (D34): its kind, a hash of
    its parent's id and its name, and its place among the items of the file with the same kind and
    hash. An edit inside a body, a blank line, an item added or removed or moved leaves the ids of the
    other items alone; only an overload added before one moves it. It means something only in its
    file, and goes back to a node through the file's `ItemIdMap`.

    """
    def __init__(self, __kind: ItemKind, __hash: int, __index: int):
        ...
    @property
    def kind(self) -> ItemKind:
        ...
    @property
    def hash(self) -> int:
        ...
    @property
    def index(self) -> int:
        ...
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: ItemId) -> bool:
        ...
    def __ne__(self, __other: ItemId) -> bool:
        ...
    def __hash__(self) -> int:
        ...
