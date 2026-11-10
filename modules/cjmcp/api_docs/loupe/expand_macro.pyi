from typing import Literal

class ExpandedMacro:
    """

    What a macro call expands to, as the analysis reads it.

    """
    def __init__(self, __name: str, __range: TextRange, __text: str, __kind: ExpansionKind, *, declaration: str | None = ...):
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def name(self) -> str:
        """

        The macro's name as the call writes it, `@` and its path, its attribute left out: `@Derive`, `@m.M`.

        """
        ...
    @property
    def range(self) -> TextRange:
        """

        The head of the call in its file (`MacroCallAt.range`).

         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def text(self) -> str:
        """

        The text of the expansion, which `hoverInExpansion` and `definitionInExpansion` take offsets in and
        `NavigationTarget.expansion` gives ranges of.

        """
        ...
    @property
    def kind(self) -> ExpansionKind:
        ...
    @property
    def declaration(self) -> str | None:
        """

        The declaration the call is on, as written after the call's head, for an expansion that adds after it
        rather than replaces it, which cjc's output starts with: one of std's but `@Strategy`'s. `None` otherwise.

        """
        ...
    def __eq__(self, __other: ExpandedMacro) -> bool:
        ...
    def __ne__(self, __other: ExpandedMacro) -> bool:
        ...
class MacroCallAt:
    """

    The macro call at a position (`macroCallAt`): the call whose expansion shows it, and where the call at the position
    is.

    """
    def __init__(self, __call: MacroCallId, __range: TextRange, *, focus: TextRange | None = ...):
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
         for type MacroCallId, see 'loupe.hir/expansion.pyi'
        """
        ...
    @property
    def call(self) -> MacroCallId:
        """

        The call whose expansion the analysis reads that shows what the call at the position adds (`readCallOf`):
        that call itself, or the outermost call the macro server runs on its top-level item, whose input the call
        at the position is in, as cjc expands one into the other (D98).

         for type MacroCallId, see 'loupe.hir/expansion.pyi'
        """
        ...
    @property
    def range(self) -> TextRange:
        """

        The head of the call at the position in its file, `@` to the end of its attribute, or of its name.

         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def focus(self) -> TextRange | None:
        """

        Where what the call at the position added is in the text of `call`'s expansion, when that is another call's
        (`expansionRangeOf`); `None` for the call itself, or where it cannot be told.

         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    def __eq__(self, __other: MacroCallAt) -> bool:
        ...
    def __ne__(self, __other: MacroCallAt) -> bool:
        ...
class ExpansionKind:
    """

    Who wrote an expansion.

    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: ExpansionKind) -> bool:
        ...
    def __ne__(self, __other: ExpansionKind) -> bool:
        ...
    kind: Literal['ServerExpansion', 'OwnExpansion']
    class ServerExpansion(ExpansionKind):
        kind: Literal['ServerExpansion'] = 'ServerExpansion'
        def __init__(self):
            ...
    class OwnExpansion(ExpansionKind):
        kind: Literal['OwnExpansion'] = 'OwnExpansion'
        def __init__(self):
            ...
