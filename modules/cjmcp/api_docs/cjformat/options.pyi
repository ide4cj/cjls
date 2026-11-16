from typing import Literal

class SimpleIf:
    """
    Layout of an if expression with one expression in each branch and no comments.
    """
    ...
    kind: Literal['Compact', 'Multiline']
    class Compact(SimpleIf):
        kind: Literal['Compact'] = 'Compact'
        def __init__(self):
            ...
    class Multiline(SimpleIf):
        kind: Literal['Multiline'] = 'Multiline'
        def __init__(self):
            ...
class FormatOptions:
    """
    Formatting policy. Width counts Unicode scalars; indentation always uses spaces.
    """
    def __init__(self, *, lineWidth: int = ..., indentWidth: int = ..., simpleIf: SimpleIf = ...):
        """

        Creates validated formatter policy.

        @throws IllegalArgumentException - if either width is not positive

        """
        ...
    @property
    def lineWidth(self) -> int:
        ...
    @property
    def indentWidth(self) -> int:
        ...
    @property
    def simpleIf(self) -> SimpleIf:
        ...
