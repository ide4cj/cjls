class InferenceResult:
    """
    
    What inference finds in a body (D55), rust-analyzer's `InferenceResult`: the type of each of its
    expressions, patterns and locals, by id; the members found after the `.` of a value; the
    declaration each resolved call takes. A type not found is an error, or one the analysis cannot
    find, and why (D77).
    
    """
    def __init__(self, *, exprs: list[Ty | None] = ..., pats: list[Ty] = ..., locals: list[Ty] = ..., fields: list[FieldTargets] = ..., callees: list[CalleeTarget] = ..., calls: list[CallResolution] = ..., setterCalls: list[CallResolution] = ..., setters: list[CalleeTarget] = ..., args: list[ArgTarget] = ..., names: list[NameTarget] = ..., accesses: list[AccessTarget] = ..., typePaths: list[TypePathTarget] = ..., ty: Ty | None = ..., diagnostics: list[InferenceDiagnostic] = ...):
        """
         for type TypePathTarget, see 'loupe.hir/signature_types.pyi'
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def exprs(self) -> list[Ty | None]:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def pats(self) -> list[Ty]:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def locals(self) -> list[Ty]:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def fields(self) -> list[FieldTargets]:
        ...
    @property
    def callees(self) -> list[CalleeTarget]:
        ...
    @property
    def calls(self) -> list[CallResolution]:
        ...
    @property
    def setterCalls(self) -> list[CallResolution]:
        ...
    @property
    def setters(self) -> list[CalleeTarget]:
        ...
    @property
    def args(self) -> list[ArgTarget]:
        ...
    @property
    def names(self) -> list[NameTarget]:
        ...
    @property
    def accesses(self) -> list[AccessTarget]:
        ...
    @property
    def typePaths(self) -> list[TypePathTarget]:
        """
         for type TypePathTarget, see 'loupe.hir/signature_types.pyi'
        """
        ...
    @property
    def ty(self) -> Ty | None:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def diagnostics(self) -> list[InferenceDiagnostic]:
        ...
    def __getitem__(self, __id: ExprId) -> Ty | None:
        """
        
        The type of `id`; `None` if it is no value, a type or a package before a `.`.
        
         for type Ty, see 'loupe.hir/ty.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    def __getitem__(self, __id: PatId) -> Ty | None:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
         for type PatId, see 'loupe.hir/body.pyi'
        """
        ...
    def __getitem__(self, __id: LocalId) -> Ty | None:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
         for type LocalId, see 'loupe.hir/body.pyi'
        """
        ...
    def fieldOf(self, __expr: ExprId) -> list[MemberTarget] | None:
        """
        
        The members the name after the `.` of `expr` names, if it follows a value.
        
         for type MemberTarget, see 'loupe.hir/members.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    def setterCallOf(self, __expr: ExprId) -> CallResolution | None:
        """
        
        The second call of an index assignment or update, keyed by the assignment expression.
        
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    def callOf(self, __expr: ExprId) -> CallResolution | None:
        """
        
        Final resolution evidence for the application whose callee is `expr`.
        
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    def calleeOf(self, __expr: ExprId) -> DefId | None:
        """
        
        The declaration selected for a call whose callee is `expr`, including unambiguous functions
        and enum constructors; also the operator function `expr` invokes (8e). Type calls expose
        their explicit initializer via `initializerOf`; `this(...)` and `super(...)` expose it here.
        
         for type DefId, see 'loupe.hir/def_map.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    def initializerOf(self, __expr: ExprId) -> DefId | None:
        """
        
        The explicit initializer selected for the call whose callee is `expr`. Navigation uses it separately
        so hover and references keep the identity of the type named by the call. None if no initializer was chosen.
        
         for type DefId, see 'loupe.hir/def_map.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    def calleesOf(self, __expr: ExprId) -> list[DefId]:
        """
        
        What `calleeOf` names, and the `[]` taking a value the assignment `a[i] op= v` or `a[i]++`
        calls, after its operator (#245), as Kotlin's K2 resolves `+=`.
        For a `CallExpr`, pass its callee's ID, not the call expression's ID.
        
         for type DefId, see 'loupe.hir/def_map.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    def paramsOf(self, __expr: ExprId) -> list[int] | None:
        """
        
        For each argument of the call whose callee is `expr`, or of the operator `expr`, the place of
        the parameter it goes to among those of what the call takes: of a variadic one for each
        element of its tail (N155); past them all, an extra one of a `foreign` function's `...`.
        
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    def nameOf(self, __expr: ExprId) -> BodyResolution | None:
        """
        
        What the name `expr` uses as a value means, if inference resolved it.
        
         for type BodyResolution, see 'loupe.hir/body_resolution.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    def accessOf(self, __expr: ExprId) -> FieldResolution | None:
        """
        
        What the name after the `.` of `expr` means, if inference resolved it.
        
         for type FieldResolution, see 'loupe.hir/field_resolution.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    def typePathOf(self, __ty: TypeRefId) -> list[PathResolution] | None:
        """
        
        What each segment of the path of the type `ty` of the body names, if inference lowered it.
        
         for type PathResolution, see 'loupe.hir/type_path.pyi'
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    def __eq__(self, __other: InferenceResult) -> bool:
        ...
    def __ne__(self, __other: InferenceResult) -> bool:
        ...
class CallResolution:
    """
    
    The final inference evidence for one application, keyed by its callee.
    
    """
    def __init__(self, __expr: ExprId, __outcome: CallResolutionOutcome, *, decl: DefId | None = ..., local: LocalId | None = ..., signature: Ty | None = ..., bindings: list[GenericBinding] = ..., params: list[int] = ...):
        """
         for type LocalId, see 'loupe.hir/body.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
         for type Ty, see 'loupe.hir/ty.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    @property
    def expr(self) -> ExprId:
        """
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    @property
    def outcome(self) -> CallResolutionOutcome:
        ...
    @property
    def decl(self) -> DefId | None:
        """
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def local(self) -> LocalId | None:
        """
         for type LocalId, see 'loupe.hir/body.pyi'
        """
        ...
    @property
    def signature(self) -> Ty | None:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def bindings(self) -> list[GenericBinding]:
        ...
    @property
    def params(self) -> list[int]:
        ...
    def keyIndex(self) -> int:
        ...
    def __eq__(self, __other: CallResolution) -> bool:
        ...
    def __ne__(self, __other: CallResolution) -> bool:
        ...
class CallResolutionOutcome:
    """
    
    Selection outcome; unavailable input reasons remain in the inferred expression and signature types.
    
    """
    def __eq__(self, __other: CallResolutionOutcome) -> bool:
        ...
    def __ne__(self, __other: CallResolutionOutcome) -> bool:
        ...
    kind: Literal['Resolved'] | Literal['Ambiguous'] | Literal['Unresolved']
    class Resolved(CallResolutionOutcome):
        kind: Literal['Resolved'] = 'Resolved'
        def __init__(self):
            ...
    class Ambiguous(CallResolutionOutcome):
        kind: Literal['Ambiguous'] = 'Ambiguous'
        def __init__(self):
            ...
    class Unresolved(CallResolutionOutcome):
        kind: Literal['Unresolved'] = 'Unresolved'
        def __init__(self):
            ...
class InferenceDiagnostic:
    """
    
    What inference finds wrong in a body, by the expression it is about, as rust-analyzer's
    `InferenceDiagnostic`: where it is written is the source map's to say.
    
    """
    def __eq__(self, __other: InferenceDiagnostic) -> bool:
        ...
    def __ne__(self, __other: InferenceDiagnostic) -> bool:
        ...
    kind: Literal['TypeMismatch'] | Literal['VArraySizeMismatch'] | Literal['ArgCount'] | Literal['ArgName'] | Literal['InvalidBinaryOperator'] | Literal['CustomAnnotationPlace']
    class TypeMismatch(InferenceDiagnostic):
        kind: Literal['TypeMismatch'] = 'TypeMismatch'
        def __init__(self, __p1: ExprId, __p2: Ty, __p3: Ty):
            """
             for type Ty, see 'loupe.hir/ty.pyi'
             for type ExprId, see 'loupe.hir/body.pyi'
            """
            ...
        @readonly
        field0: ExprId
        @readonly
        field1: Ty
        @readonly
        field2: Ty
        __match_args__ = ('field0', 'field1', 'field2')
    class VArraySizeMismatch(InferenceDiagnostic):
        kind: Literal['VArraySizeMismatch'] = 'VArraySizeMismatch'
        def __init__(self, __p1: ExprId, __p2: int, __p3: int):
            """
             for type ExprId, see 'loupe.hir/body.pyi'
            """
            ...
        @readonly
        field0: ExprId
        @readonly
        field1: int
        @readonly
        field2: int
        __match_args__ = ('field0', 'field1', 'field2')
    class ArgCount(InferenceDiagnostic):
        kind: Literal['ArgCount'] = 'ArgCount'
        def __init__(self, __p1: ExprId, __p2: list[Ty], __p3: int):
            """
             for type Ty, see 'loupe.hir/ty.pyi'
             for type ExprId, see 'loupe.hir/body.pyi'
            """
            ...
        @readonly
        field0: ExprId
        @readonly
        field1: list[Ty]
        @readonly
        field2: int
        __match_args__ = ('field0', 'field1', 'field2')
    class ArgName(InferenceDiagnostic):
        kind: Literal['ArgName'] = 'ArgName'
        def __init__(self, __p1: ExprId, __p2: int, __p3: ArgNameError):
            """
             for type ExprId, see 'loupe.hir/body.pyi'
            """
            ...
        @readonly
        field0: ExprId
        @readonly
        field1: int
        @readonly
        field2: ArgNameError
        __match_args__ = ('field0', 'field1', 'field2')
    class InvalidBinaryOperator(InferenceDiagnostic):
        kind: Literal['InvalidBinaryOperator'] = 'InvalidBinaryOperator'
        def __init__(self, __p1: ExprId, __p2: Ty, __p3: Ty):
            """
             for type Ty, see 'loupe.hir/ty.pyi'
             for type ExprId, see 'loupe.hir/body.pyi'
            """
            ...
        @readonly
        field0: ExprId
        @readonly
        field1: Ty
        @readonly
        field2: Ty
        __match_args__ = ('field0', 'field1', 'field2')
    class CustomAnnotationPlace(InferenceDiagnostic):
        kind: Literal['CustomAnnotationPlace'] = 'CustomAnnotationPlace'
        def __init__(self, __p1: ExprId):
            """
             for type ExprId, see 'loupe.hir/body.pyi'
            """
            ...
        @readonly
        field0: ExprId
        __match_args__ = ('field0')
class NameTarget:
    """
    
    What a name the body uses as a value means, as inference resolved it: what highlighting and go to
    definition read, not resolving it again.
    
    """
    def __init__(self, __expr: ExprId, __resolution: BodyResolution):
        """
         for type BodyResolution, see 'loupe.hir/body_resolution.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    @property
    def expr(self) -> ExprId:
        """
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    @property
    def resolution(self) -> BodyResolution:
        """
         for type BodyResolution, see 'loupe.hir/body_resolution.pyi'
        """
        ...
    def keyIndex(self) -> int:
        ...
    def __eq__(self, __other: NameTarget) -> bool:
        ...
    def __ne__(self, __other: NameTarget) -> bool:
        ...
class AccessTarget:
    """
    
    What the name after the `.` of an expression means, as inference resolved it before the types: a
    member of a package or of types, or one of a value, which `FieldTargets` tells.
    
    """
    def __init__(self, __expr: ExprId, __resolution: FieldResolution):
        """
         for type FieldResolution, see 'loupe.hir/field_resolution.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    @property
    def expr(self) -> ExprId:
        """
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    @property
    def resolution(self) -> FieldResolution:
        """
         for type FieldResolution, see 'loupe.hir/field_resolution.pyi'
        """
        ...
    def keyIndex(self) -> int:
        ...
    def __eq__(self, __other: AccessTarget) -> bool:
        ...
    def __ne__(self, __other: AccessTarget) -> bool:
        ...
class FieldTargets:
    """
    
    The members the name after the `.` of a value names, found from the value's type (N75).
    
    """
    def __init__(self, __expr: ExprId, __targets: list[MemberTarget]):
        """
         for type MemberTarget, see 'loupe.hir/members.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    @property
    def expr(self) -> ExprId:
        """
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    @property
    def targets(self) -> list[MemberTarget]:
        """
         for type MemberTarget, see 'loupe.hir/members.pyi'
        """
        ...
    def keyIndex(self) -> int:
        ...
    def __eq__(self, __other: FieldTargets) -> bool:
        ...
    def __ne__(self, __other: FieldTargets) -> bool:
        ...
class CalleeTarget:
    """
    
    The declaration selected for a call, by its callee (8d); initializer targets are used only for navigation.
    
    """
    def __init__(self, __expr: ExprId, __decl: DefId, *, isInitializer: bool = ...):
        """
         for type DefId, see 'loupe.hir/def_map.pyi'
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    @property
    def expr(self) -> ExprId:
        """
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    @property
    def decl(self) -> DefId:
        """
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def isInitializer(self) -> bool:
        ...
    def keyIndex(self) -> int:
        ...
    def __eq__(self, __other: CalleeTarget) -> bool:
        ...
    def __ne__(self, __other: CalleeTarget) -> bool:
        ...
class ArgNameError:
    """
    
    What is wrong with the name an argument is passed by (cjc's `CheckArgsWithParamName`, N156).
    
    """
    def __eq__(self, __other: ArgNameError) -> bool:
        ...
    def __ne__(self, __other: ArgNameError) -> bool:
        ...
    kind: Literal['UnknownName'] | Literal['NameTwice'] | Literal['NeedsName'] | Literal['NameOfValue']
    class UnknownName(ArgNameError):
        kind: Literal['UnknownName'] = 'UnknownName'
        def __init__(self, __p1: str):
            ...
        @readonly
        field0: str
        __match_args__ = ('field0')
    class NameTwice(ArgNameError):
        kind: Literal['NameTwice'] = 'NameTwice'
        def __init__(self, __p1: str):
            ...
        @readonly
        field0: str
        __match_args__ = ('field0')
    class NeedsName(ArgNameError):
        kind: Literal['NeedsName'] = 'NeedsName'
        def __init__(self, __p1: list[str]):
            ...
        @readonly
        field0: list[str]
        __match_args__ = ('field0')
    class NameOfValue(ArgNameError):
        kind: Literal['NameOfValue'] = 'NameOfValue'
        def __init__(self):
            ...
class ArgTarget:
    """
    
    Where each argument of a call goes, by its callee: the place of its parameter among those of
    what the call takes (#254).
    
    """
    def __init__(self, __expr: ExprId, __params: list[int]):
        """
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    @property
    def expr(self) -> ExprId:
        """
         for type ExprId, see 'loupe.hir/body.pyi'
        """
        ...
    @property
    def params(self) -> list[int]:
        ...
    def keyIndex(self) -> int:
        ...
    def __eq__(self, __other: ArgTarget) -> bool:
        ...
    def __ne__(self, __other: ArgTarget) -> bool:
        ...
class GenericBinding:
    """
    
    A final substitution, keyed by the binder that declared the parameter.
    
    """
    def __init__(self, __owner: GenericOwner, __index: int, __ty: Ty):
        """
         for type Ty, see 'loupe.hir/ty.pyi'
         for type GenericOwner, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def owner(self) -> GenericOwner:
        """
         for type GenericOwner, see 'loupe.hir/ty.pyi'
        """
        ...
    @property
    def index(self) -> int:
        ...
    @property
    def ty(self) -> Ty:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    def __eq__(self, __other: GenericBinding) -> bool:
        ...
    def __ne__(self, __other: GenericBinding) -> bool:
        ...
