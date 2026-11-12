from typing import Literal

class Modifier:
    """
    A modifier, as written before a declaration.
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: Modifier) -> bool:
        ...
    def __ne__(self, __other: Modifier) -> bool:
        ...
    kind: Literal['Static', 'Public', 'Private', 'Internal', 'Protected', 'Override', 'Redef', 'Abstract', 'Sealed', 'Open', 'Foreign', 'Mut', 'Unsafe', 'Operator', 'Const', 'Common', 'Specific']
    class Static(Modifier):
        kind: Literal['Static'] = 'Static'
        def __init__(self):
            ...
    class Public(Modifier):
        kind: Literal['Public'] = 'Public'
        def __init__(self):
            ...
    class Private(Modifier):
        kind: Literal['Private'] = 'Private'
        def __init__(self):
            ...
    class Internal(Modifier):
        kind: Literal['Internal'] = 'Internal'
        def __init__(self):
            ...
    class Protected(Modifier):
        kind: Literal['Protected'] = 'Protected'
        def __init__(self):
            ...
    class Override(Modifier):
        kind: Literal['Override'] = 'Override'
        def __init__(self):
            ...
    class Redef(Modifier):
        kind: Literal['Redef'] = 'Redef'
        def __init__(self):
            ...
    class Abstract(Modifier):
        kind: Literal['Abstract'] = 'Abstract'
        def __init__(self):
            ...
    class Sealed(Modifier):
        kind: Literal['Sealed'] = 'Sealed'
        def __init__(self):
            ...
    class Open(Modifier):
        kind: Literal['Open'] = 'Open'
        def __init__(self):
            ...
    class Foreign(Modifier):
        kind: Literal['Foreign'] = 'Foreign'
        def __init__(self):
            ...
    class Mut(Modifier):
        kind: Literal['Mut'] = 'Mut'
        def __init__(self):
            ...
    class Unsafe(Modifier):
        kind: Literal['Unsafe'] = 'Unsafe'
        def __init__(self):
            ...
    class Operator(Modifier):
        kind: Literal['Operator'] = 'Operator'
        def __init__(self):
            ...
    class Const(Modifier):
        kind: Literal['Const'] = 'Const'
        def __init__(self):
            ...
    class Common(Modifier):
        kind: Literal['Common'] = 'Common'
        def __init__(self):
            ...
    class Specific(Modifier):
        kind: Literal['Specific'] = 'Specific'
        def __init__(self):
            ...
class PackageItem:
    """
    The `package` line: the package's name as written (`a.b`, `org::a.b`), and whether it is a `macro package`.
    """
    def __init__(self, __name: str, __isMacro: bool, __modifiers: list[Modifier]):
        ...
    @property
    def name(self) -> str:
        ...
    @property
    def isMacro(self) -> bool:
        ...
    @property
    def modifiers(self) -> list[Modifier]:
        ...
    def __eq__(self, __other: PackageItem) -> bool:
        ...
    def __ne__(self, __other: PackageItem) -> bool:
        ...
class ImportPath:
    """
    One name an import brings in, as written: `segments` up to it, `org::a` one segment; every name of the package for a glob (`a.b.*`), else the package's and the imported one's.
    """
    def __init__(self, __segments: list[str], *, alias: str | None = ..., isGlob: bool = ...):
        ...
    @property
    def segments(self) -> list[str]:
        ...
    @property
    def alias(self) -> str | None:
        ...
    @property
    def isGlob(self) -> bool:
        ...
    def __eq__(self, __other: ImportPath) -> bool:
        ...
    def __ne__(self, __other: ImportPath) -> bool:
        ...
class ImportItem:
    """
    An `import`, and every name it brings in: `import a.{b as c, d.*}` brings two.
    """
    def __init__(self, __id: ItemId, __modifiers: list[Modifier], __paths: list[ImportPath], *, condition: CfgExpr | None = ...):
        """
         for type CfgExpr, see 'loupe.hir/when.pyi'
         for type ItemId, see 'loupe.hir/item_id.pyi'
        """
        ...
    @property
    def id(self) -> ItemId:
        """
         for type ItemId, see 'loupe.hir/item_id.pyi'
        """
        ...
    @property
    def modifiers(self) -> list[Modifier]:
        ...
    @property
    def paths(self) -> list[ImportPath]:
        ...
    @property
    def condition(self) -> CfgExpr | None:
        """
        Its `@When`'s, `None` for none.
         for type CfgExpr, see 'loupe.hir/when.pyi'
        """
        ...
    def __eq__(self, __other: ImportItem) -> bool:
        ...
    def __ne__(self, __other: ImportItem) -> bool:
        ...
class Item:
    """
    A declaration of the file, as name resolution needs it, and nothing that moves when the file is edited elsewhere: no range, no body, no signature.
    """
    def __init__(self, __id: ItemId, __names: list[str], __modifiers: list[Modifier], __macros: list[str], __members: list[Item], *, condition: CfgExpr | None = ..., paramMacros: list[list[str]] = ..., isC: bool = ...):
        """
         for type CfgExpr, see 'loupe.hir/when.pyi'
         for type ItemId, see 'loupe.hir/item_id.pyi'
        """
        ...
    @property
    def id(self) -> ItemId:
        """
         for type ItemId, see 'loupe.hir/item_id.pyi'
        """
        ...
    @property
    def names(self) -> list[str]:
        """
        What it declares by name: one for most, none for an `extend` or a macro call, each binding of a `let` of a pattern. Empty while its name is not written yet.
        """
        ...
    @property
    def modifiers(self) -> list[Modifier]:
        """
        Those of the declaration and of the macro calls on it; `foreign` for one in a `foreign` block.
        """
        ...
    @property
    def macros(self) -> list[str]:
        """
        The macros called on it, outermost first; for a macro call on no declaration, its macro.
        """
        ...
    @property
    def members(self) -> list[Item]:
        """
        A type's members, an enum's constructors.
        """
        ...
    @property
    def condition(self) -> CfgExpr | None:
        """
        The `@When` before it, or before the outermost macro call on it, `None` for none: whether it is in a build is the cfg's to say (`activeItemTree`).
         for type CfgExpr, see 'loupe.hir/when.pyi'
        """
        ...
    @property
    def paramMacros(self) -> list[list[str]]:
        """
        The macros called on each parameter of its own parameter lists that has any, in the parameters' order, each outermost first: `@M let x` of a primary constructor (D119).
        """
        ...
    @property
    def isC(self) -> bool:
        """
        Whether the declaration has the built-in `@C` annotation, distinct from a macro call.
        """
        ...
    @property
    def kind(self) -> ItemKind:
        """
        The declaration category of this item-tree entry.
         for type ItemKind, see 'loupe.hir/item_id.pyi'
        """
        ...
    def has(self, __modifier: Modifier) -> bool:
        """
        Whether `modifier` is among its modifiers.
        """
        ...
    def __eq__(self, __other: Item) -> bool:
        ...
    def __ne__(self, __other: Item) -> bool:
        ...
class ItemTree:
    """
    What a file declares, rust-analyzer's `ItemTree`: its package, its imports and its items, named by their `ItemId`s. An edit inside a body, or one that only moves items, leaves it equal, so what read it is not run again.
    """
    def __init__(self, *, packageHeader: PackageItem | None = ..., imports: list[ImportItem] = ..., items: list[Item] = ...):
        ...
    @property
    def packageHeader(self) -> PackageItem | None:
        ...
    @property
    def imports(self) -> list[ImportItem]:
        ...
    @property
    def items(self) -> list[Item]:
        ...
    def __eq__(self, __other: ItemTree) -> bool:
        ...
    def __ne__(self, __other: ItemTree) -> bool:
        ...
