from typing import Literal

class LangItem:
    """

    A declaration of std the language itself means, whatever a file's scope names: what the syntax is
    sugar for or is of. cjc's `GetCoreDecl`, R1's lang items (8f). Not the compiler's own types
    (`CPointer`, `CString`): a file names those, through its scope.

    """
    def name(self) -> str:
        """
        Return the language-defined name used to recognize this item.
        """
        ...
    def kind(self) -> ItemKind:
        """
        Return the declaration kind expected for this language item.
         for type ItemKind, see 'loupe.hir/item_id.pyi'
        """
        ...
    def pkg(self) -> str:
        """

        The package of std it is declared in.

        """
        ...
    def owner(self) -> LangItem | None:
        """

        The lang item it is a member of: an enum's of a constructor.

        """
        ...
    def __eq__(self, __other: LangItem) -> bool:
        ...
    def __ne__(self, __other: LangItem) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    kind: Literal['OptionEnum', 'OptionSome', 'OptionNone', 'CompositionFunc', 'ObjectClass', 'StringStruct', 'FutureClass', 'IterableInterface', 'RangeStruct', 'ArrayStruct', 'ExceptionClass', 'TokensClass', 'AnyInterface']
    class OptionEnum(LangItem):
        kind: Literal['OptionEnum'] = 'OptionEnum'
        def __init__(self):
            ...
    class OptionSome(LangItem):
        kind: Literal['OptionSome'] = 'OptionSome'
        def __init__(self):
            ...
    class OptionNone(LangItem):
        kind: Literal['OptionNone'] = 'OptionNone'
        def __init__(self):
            ...
    class CompositionFunc(LangItem):
        kind: Literal['CompositionFunc'] = 'CompositionFunc'
        def __init__(self):
            ...
    class ObjectClass(LangItem):
        kind: Literal['ObjectClass'] = 'ObjectClass'
        def __init__(self):
            ...
    class StringStruct(LangItem):
        kind: Literal['StringStruct'] = 'StringStruct'
        def __init__(self):
            ...
    class FutureClass(LangItem):
        kind: Literal['FutureClass'] = 'FutureClass'
        def __init__(self):
            ...
    class IterableInterface(LangItem):
        kind: Literal['IterableInterface'] = 'IterableInterface'
        def __init__(self):
            ...
    class RangeStruct(LangItem):
        kind: Literal['RangeStruct'] = 'RangeStruct'
        def __init__(self):
            ...
    class ArrayStruct(LangItem):
        kind: Literal['ArrayStruct'] = 'ArrayStruct'
        def __init__(self):
            ...
    class ExceptionClass(LangItem):
        kind: Literal['ExceptionClass'] = 'ExceptionClass'
        def __init__(self):
            ...
    class TokensClass(LangItem):
        kind: Literal['TokensClass'] = 'TokensClass'
        def __init__(self):
            ...
    class AnyInterface(LangItem):
        kind: Literal['AnyInterface'] = 'AnyInterface'
        def __init__(self):
            ...
