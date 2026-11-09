class CfgExpr:
    """
    
    The condition of a `@When`, lowered from its expression with nothing of the tree: what cjc
    evaluates it as (`src/ConditionalCompilation`). One cjc rejects is `CfgInvalid`, false as cjc
    evaluates it, unlike R1's `CfgExpr::Invalid`, which is active (#149, D93).
    
    """
    def evaluate(self, __cfg: Cfg) -> bool | None:
        """
        
        Whether it holds under `cfg`; `None` when that cannot be told, a condition `cfg` has no value
        of. One cjc rejects is false, as cjc has it. `&&` and `||` are Kleene's: unknown only when the
        side known does not decide.
        
         for type Cfg, see 'loupe.db/project.pyi'
        """
        ...
    def isActive(self, __cfg: Cfg) -> bool:
        """
        
        Whether code under it is in the build `cfg` makes: unless it is known to be false.
        
         for type Cfg, see 'loupe.db/project.pyi'
        """
        ...
    def whyFalse(self, __cfg: Cfg) -> list[str]:
        """
        
        Why it is false under `cfg`: what each condition making it so is instead, each once,
        `os is "Linux"`, `test is not set`. Empty unless it is false.
        
         for type Cfg, see 'loupe.db/project.pyi'
        """
        ...
    def __eq__(self, __other: CfgExpr) -> bool:
        ...
    def __ne__(self, __other: CfgExpr) -> bool:
        ...
    kind: Literal['CfgCompare'] | Literal['CfgFlag'] | Literal['CfgAnd'] | Literal['CfgOr'] | Literal['CfgInvalid']
    class CfgCompare(CfgExpr):
        kind: Literal['CfgCompare'] = 'CfgCompare'
        def __init__(self, __p1: str, __p2: str, __p3: str):
            ...
        @readonly
        field0: str
        @readonly
        field1: str
        @readonly
        field2: str
        __match_args__ = ('field0', 'field1', 'field2')
    class CfgFlag(CfgExpr):
        kind: Literal['CfgFlag'] = 'CfgFlag'
        def __init__(self, __p1: str, __p2: bool):
            ...
        @readonly
        field0: str
        @readonly
        field1: bool
        __match_args__ = ('field0', 'field1')
    class CfgAnd(CfgExpr):
        kind: Literal['CfgAnd'] = 'CfgAnd'
        def __init__(self, __p1: CfgExpr, __p2: CfgExpr):
            ...
        @readonly
        field0: CfgExpr
        @readonly
        field1: CfgExpr
        __match_args__ = ('field0', 'field1')
    class CfgOr(CfgExpr):
        kind: Literal['CfgOr'] = 'CfgOr'
        def __init__(self, __p1: CfgExpr, __p2: CfgExpr):
            ...
        @readonly
        field0: CfgExpr
        @readonly
        field1: CfgExpr
        __match_args__ = ('field0', 'field1')
    class CfgInvalid(CfgExpr):
        kind: Literal['CfgInvalid'] = 'CfgInvalid'
        def __init__(self):
            ...
class WhenError:
    """
    
    What a `@When` is wrong with, as cjc says it, where.
    
    """
    def __init__(self, __range: TextRange, __message: str):
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
    def message(self) -> str:
        ...
    def __eq__(self, __other: WhenError) -> bool:
        ...
    def __ne__(self, __other: WhenError) -> bool:
        ...
class InactiveCode:
    """
    
    Code a false `@When` leaves out of the build, and why: `reasons`, as `CfgExpr.whyFalse`.
    
    """
    def __init__(self, __range: TextRange, __reasons: list[str]):
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
    def reasons(self) -> list[str]:
        ...
    def __eq__(self, __other: InactiveCode) -> bool:
        ...
    def __ne__(self, __other: InactiveCode) -> bool:
        ...
class WhenDiagnostics:
    """
    
    What the `@When`s of a file say: the code they leave out, outermost only (nothing inside it is
    checked, as cjc checks nothing there), and what cjc rejects in them whatever the build, as it says
    it. Code that a condition cjc rejects leaves out is not reported as left out: the error on the
    condition says why. A condition neither cjc knows nor the cfg sets is not one: a `--cfg` the analysis does not see
    may set it (#297), and its code is active.
    
    """
    def __init__(self, __inactive: list[InactiveCode], __errors: list[WhenError]):
        ...
    @property
    def inactive(self) -> list[InactiveCode]:
        ...
    @property
    def errors(self) -> list[WhenError]:
        ...
    def __eq__(self, __other: WhenDiagnostics) -> bool:
        ...
    def __ne__(self, __other: WhenDiagnostics) -> bool:
        ...
