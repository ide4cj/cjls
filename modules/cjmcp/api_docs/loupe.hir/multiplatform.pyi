class NoSpecific:
    """
    
    A `common` declaration no `specific` one completes, though it needs one, as cjc says it: `'common'
    function 'f' can not find 'specific' match`.
    
    """
    def __init__(self, __def: DefId, __message: str):
        """
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def def(self) -> DefId:
        """
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def message(self) -> str:
        ...
    def __eq__(self, __other: NoSpecific) -> bool:
        ...
    def __ne__(self, __other: NoSpecific) -> bool:
        ...
