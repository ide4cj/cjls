class PythonSignatureSourceMap:
    """
    
    Concrete signature mapping for Python, keeping generic syntax pointers inside loupe.
    
    """
    @property
    def ranges(self) -> list[TextRange | None]:
        """
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
class PythonLoweredSignature:
    """
    
    A native written signature and its concrete Python source mapping.
    
    """
    @property
    def signature(self) -> Signature:
        """
         for type Signature, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def sourceMap(self) -> PythonSignatureSourceMap:
        ...
