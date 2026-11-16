from typing import Literal

class SignatureSourceMap:
    """
    Maps signature type-reference IDs to optional UTF-8 source ranges.
    """
    @property
    def ranges(self) -> list[TextRange | None]:
        """
        Optional UTF-8 source ranges indexed by signature TypeRefId.
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    def typeAtRange(self, __range: TextRange) -> TypeRefId | None:
        """
        The first type reference written at exactly this range, or None.
         for type TypeRefId, see 'loupe.hir/signature.pyi'
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
class LoweredSignature:
    """
    A native written signature and the source ranges of its type references.
    """
    @property
    def signature(self) -> Signature:
        """
         for type Signature, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def sourceMap(self) -> SignatureSourceMap:
        ...
