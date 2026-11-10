from typing import Literal

class FoldKind:
    """

    What a fold is: LSP names the first two, the others are for whoever tells folds apart.

    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: FoldKind) -> bool:
        ...
    def __ne__(self, __other: FoldKind) -> bool:
        ...
    kind: Literal['Comment', 'Imports', 'Block', 'MatchArm', 'ArgList', 'ArrayLiteral', 'StringLiteral']
    class Comment(FoldKind):
        kind: Literal['Comment'] = 'Comment'
        def __init__(self):
            ...
    class Imports(FoldKind):
        kind: Literal['Imports'] = 'Imports'
        def __init__(self):
            ...
    class Block(FoldKind):
        kind: Literal['Block'] = 'Block'
        def __init__(self):
            ...
    class MatchArm(FoldKind):
        kind: Literal['MatchArm'] = 'MatchArm'
        def __init__(self):
            ...
    class ArgList(FoldKind):
        kind: Literal['ArgList'] = 'ArgList'
        def __init__(self):
            ...
    class ArrayLiteral(FoldKind):
        kind: Literal['ArrayLiteral'] = 'ArrayLiteral'
        def __init__(self):
            ...
    class StringLiteral(FoldKind):
        kind: Literal['StringLiteral'] = 'StringLiteral'
        def __init__(self):
            ...
class Fold:
    """

    A part of a file over more than one line an editor may fold. `range` is in UTF-8 bytes (A6) and
    covers the delimiters, `{` to `}`: what is left visible is the client's to choose.

    """
    def __init__(self, __range: TextRange, __kind: FoldKind):
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def range(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def kind(self) -> FoldKind:
        ...
    def __repr__(self) -> str:
        """

        `kind@start..end`.

        """
        ...
    def __eq__(self, __other: Fold) -> bool:
        ...
    def __ne__(self, __other: Fold) -> bool:
        ...
