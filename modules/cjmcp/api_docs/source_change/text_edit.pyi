from typing import Literal

class TextEdit:
    """

    A replacement in UTF-8 byte offsets into the original text, with an exclusive end.

    """
    def __init__(self, __range: TextRange, __text: str):
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
    def text(self) -> str:
        ...
    def __eq__(self, __other: TextEdit) -> bool:
        ...
    def __ne__(self, __other: TextEdit) -> bool:
        ...
    def __repr__(self) -> str:
        ...
