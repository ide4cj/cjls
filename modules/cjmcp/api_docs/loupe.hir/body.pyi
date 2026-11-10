from typing import Literal

class LoweredBody:
    """
    A lowered body together with mappings between its IDs and source syntax.
    """
    def __init__(self, __body: Body, __sourceMap: BodySourceMap):
        ...
    @property
    def body(self) -> Body:
        ...
    @property
    def sourceMap(self) -> BodySourceMap:
        ...
    def __eq__(self, __other: LoweredBody) -> bool:
        ...
    def __ne__(self, __other: LoweredBody) -> bool:
        ...
class BodySourceMap:
    """
    Where each expression, pattern, local and type of a body is written: a local by its name; and the other way round, by hash, for what asks of every name of a file.
    """
    @property
    def exprs(self) -> list[BodyOrigin]:
        ...
    @property
    def pats(self) -> list[BodyOrigin]:
        ...
    @property
    def locals(self) -> list[BodyOrigin]:
        ...
    @property
    def types(self) -> list[BodyOrigin]:
        ...
    def __init__(self, *, exprs: list[BodyOrigin] = ..., pats: list[BodyOrigin] = ..., locals: list[BodyOrigin] = ..., types: list[BodyOrigin] = ..., annotations: list[AnnotationSource] = ..., aliases: list[ExprSourceAlias] = ...):
        ...
    def exprAt(self, __ptr: SyntaxNodePtr) -> ExprId | None:
        ...
    def exprAtSource(self, __source: BodySource) -> ExprId | None:
        """
        The expression at the file-qualified syntax source.
        """
        ...
    def exprsAtSource(self, __source: BodySource) -> list[ExprId]:
        """
        All exact mappings in expression arena order, followed by distinct expansion aliases. Unlike exprAtSource this includes the later desugared values (A29).
        """
        ...
    def sourcesOfExpr(self, __id: ExprId) -> list[BodySource]:
        """
        Exact written origin followed by distinct call-site aliases in lowering order. Synthetic expressions have no written origin; aliases do not change that classification.
        """
        ...
    def patAt(self, __ptr: SyntaxNodePtr) -> PatId | None:
        ...
    def patAtSource(self, __source: BodySource) -> PatId | None:
        """
        The pattern at the file-qualified syntax source.
        """
        ...
    def localAt(self, __ptr: SyntaxNodePtr) -> LocalId | None:
        ...
    def localAtSource(self, __source: BodySource) -> LocalId | None:
        """
        The local declaration at the file-qualified syntax source.
        """
        ...
    def typeAt(self, __ptr: SyntaxNodePtr) -> TypeRefId | None:
        """
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    def typeAtSource(self, __source: BodySource) -> TypeRefId | None:
        """
        The type reference at the file-qualified syntax source.
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    def __eq__(self, __other: BodySourceMap) -> bool:
        """

        Field by field, but the indexes, which the arrays make.

        """
        ...
    def __ne__(self, __other: BodySourceMap) -> bool:
        ...
class BodyOrigin:
    """
    A body node's origin: syntax in a file, or a synthetic node introduced by lowering. A missing array index is separate from a present synthetic node.
    """
    @property
    def written(self) -> BodySource | None:
        """
        The syntax source, when lowering preserved one.
        """
        ...
    def __eq__(self, __other: BodyOrigin) -> bool:
        ...
    def __ne__(self, __other: BodyOrigin) -> bool:
        ...
    kind: Literal['WrittenSource', 'SyntheticSource']
    class WrittenSource(BodyOrigin):
        kind: Literal['WrittenSource'] = 'WrittenSource'
        def __init__(self, __p1: BodySource):
            ...
        @property
        def field0(self) -> BodySource:
            ...
        __match_args__ = ('field0')
    class SyntheticSource(BodyOrigin):
        kind: Literal['SyntheticSource'] = 'SyntheticSource'
        def __init__(self):
            ...
class Body:
    """
    What a declaration's body is lowered to, nothing of where it is written: rust-analyzer's `Body`. An edit that does not change its code, a blank line or a comment, an edit elsewhere in the file, leaves it equal.
    """
    def __init__(self, *, exprs: list[Expr] = ..., pats: list[Pat] = ..., locals: list[Local] = ..., funcs: list[LocalFunc] = ..., types: list[TypeRef] = ..., params: list[BodyParam] = ..., value: ExprId | None = ..., accessors: list[ExprId] = ..., getters: list[ExprId] = ..., attrs: list[DeclAttr] = ..., annotations: list[LocalAnnotation] = ...):
        """
         for type TypeRef, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def exprs(self) -> list[Expr]:
        ...
    @property
    def pats(self) -> list[Pat]:
        ...
    @property
    def locals(self) -> list[Local]:
        ...
    @property
    def funcs(self) -> list[LocalFunc]:
        ...
    @property
    def types(self) -> list[TypeRef]:
        """
        The types it writes, as a signature's (D48).
         for type TypeRef, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def params(self) -> list[BodyParam]:
        """
        The declaration's parameters, their default values in the body (N67).
        """
        ...
    @property
    def value(self) -> ExprId | None:
        """
        A function's block, a variable's initializer.
        """
        ...
    @property
    def accessors(self) -> list[ExprId]:
        """
        A property's `get` and `set`, each a lambda.
        """
        ...
    @property
    def getters(self) -> list[ExprId]:
        """
        Getter identity stays explicit even when its parameter list is malformed.
        """
        ...
    @property
    def attrs(self) -> list[DeclAttr]:
        """
        What the macros on it take as code in their `[...]`, outermost first.
        """
        ...
    @property
    def annotations(self) -> list[LocalAnnotation]:
        """

        Possible custom annotations; constructor typing decides whether placement can be checked.

        """
        ...
    def __getitem__(self, __id: ExprId) -> Expr:
        ...
    def __getitem__(self, __id: PatId) -> Pat:
        ...
    def __getitem__(self, __id: LocalId) -> Local:
        ...
    def typesAsSignature(self) -> Signature:
        """
        Its types as a signature, for `Signature.text`.
         for type Signature, see 'loupe.hir/signature.pyi'
        """
        ...
    def __eq__(self, __other: Body) -> bool:
        ...
    def __ne__(self, __other: Body) -> bool:
        ...
class LocalAnnotation:
    """
    A possible custom annotation on a local declaration; resolution distinguishes it from a macro. Its type is public because it appears in Body's public constructor; its data stays HIR-local.
    """
    def __init__(self, __path: list[str], __args: list[CallArg], __target: ExprId, __owner: AnnotationOwner, __wrappers: list[list[str]]):
        ...
    def __eq__(self, __other: LocalAnnotation) -> bool:
        ...
    def __ne__(self, __other: LocalAnnotation) -> bool:
        ...
class Pat:
    """
    A pattern as a body writes it.
    """
    def __eq__(self, __other: Pat) -> bool:
        ...
    def __ne__(self, __other: Pat) -> bool:
        ...
    kind: Literal['MissingPat', 'WildcardPat', 'LitPat', 'BindPat', 'TypePat', 'TuplePat', 'EnumPat']
    class MissingPat(Pat):
        kind: Literal['MissingPat'] = 'MissingPat'
        def __init__(self):
            ...
    class WildcardPat(Pat):
        kind: Literal['WildcardPat'] = 'WildcardPat'
        def __init__(self):
            ...
    class LitPat(Pat):
        kind: Literal['LitPat'] = 'LitPat'
        def __init__(self, __p1: str):
            ...
        @property
        def field0(self) -> str:
            ...
        __match_args__ = ('field0')
    class BindPat(Pat):
        kind: Literal['BindPat'] = 'BindPat'
        def __init__(self, __p1: LocalId):
            ...
        @property
        def field0(self) -> LocalId:
            ...
        __match_args__ = ('field0')
    class TypePat(Pat):
        kind: Literal['TypePat'] = 'TypePat'
        def __init__(self, __p1: LocalId | None, __p2: TypeRefId):
            """
             for type TypeRefId, see 'loupe.hir/signature.pyi'
            """
            ...
        @property
        def field0(self) -> LocalId | None:
            ...
        @property
        def field1(self) -> TypeRefId:
            ...
        __match_args__ = ('field0', 'field1')
    class TuplePat(Pat):
        kind: Literal['TuplePat'] = 'TuplePat'
        def __init__(self, __p1: list[PatId]):
            ...
        @property
        def field0(self) -> list[PatId]:
            ...
        __match_args__ = ('field0')
    class EnumPat(Pat):
        kind: Literal['EnumPat'] = 'EnumPat'
        def __init__(self, __p1: list[str], __p2: list[PatId]):
            ...
        @property
        def field0(self) -> list[str]:
            ...
        @property
        def field1(self) -> list[PatId]:
            ...
        __match_args__ = ('field0', 'field1')
class DeclAttr:
    """
    A macro on a declaration that takes code in its `[...]`, by the name it is called by: the path it names, and the arguments, those of std.unittest's macros. Whether it is std's is inference's to find.
    """
    def __init__(self, __path: list[str], __args: list[AttrArg]):
        ...
    @property
    def path(self) -> list[str]:
        ...
    @property
    def args(self) -> list[AttrArg]:
        ...
    def __eq__(self, __other: DeclAttr) -> bool:
        ...
    def __ne__(self, __other: DeclAttr) -> bool:
        ...
class MacroCall:
    """
    A macro called in a body, `@M[a](b, c)`: the path it names, the macro outermost of those nested (`@A @B(x)`); the types its `[…]` lists, if it has one, each an identifier, those between `|` (`@AssertThrows[A | B]`, N136), none of one of anything else; its arguments when they parse as an argument list, the innermost's, lowered so the names in them resolve: the macro sees them as tokens all the same.
    """
    def __init__(self, __path: list[str], __attr: list[TypeRefId] | None, __args: list[CallArg]):
        """
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def path(self) -> list[str]:
        ...
    @property
    def attr(self) -> list[TypeRefId] | None:
        """
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def args(self) -> list[CallArg]:
        ...
    def __eq__(self, __other: MacroCall) -> bool:
        ...
    def __ne__(self, __other: MacroCall) -> bool:
        ...
class Stmt:
    """
    A lowered body statement: a local binding, expression or local-function declaration.
    """
    def __eq__(self, __other: Stmt) -> bool:
        ...
    def __ne__(self, __other: Stmt) -> bool:
        ...
    kind: Literal['LetStmt', 'ExprStmt', 'FuncStmt']
    class LetStmt(Stmt):
        kind: Literal['LetStmt'] = 'LetStmt'
        def __init__(self, __p1: PatId, __p2: TypeRefId | None, __p3: ExprId | None):
            """
             for type TypeRefId, see 'loupe.hir/signature.pyi'
            """
            ...
        @property
        def field0(self) -> PatId:
            ...
        @property
        def field1(self) -> TypeRefId | None:
            ...
        @property
        def field2(self) -> ExprId | None:
            ...
        __match_args__ = ('field0', 'field1', 'field2')
    class ExprStmt(Stmt):
        kind: Literal['ExprStmt'] = 'ExprStmt'
        def __init__(self, __p1: ExprId):
            ...
        @property
        def field0(self) -> ExprId:
            ...
        __match_args__ = ('field0')
    class FuncStmt(Stmt):
        kind: Literal['FuncStmt'] = 'FuncStmt'
        def __init__(self, __p1: int):
            ...
        @property
        def field0(self) -> int:
            ...
        __match_args__ = ('field0')
class LocalFunc:
    """
    A function declared in a body: its name, a local of the scope after it (N60).
    """
    def __init__(self, __local: LocalId, __generics: list[str], __params: list[BodyParam], __ret: TypeRefId | None, __body: ExprId | None, *, bounds: list[TypeBound] = ...):
        """
         for type TypeBound, see 'loupe.hir/signature.pyi'
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def local(self) -> LocalId:
        ...
    @property
    def generics(self) -> list[str]:
        ...
    @property
    def params(self) -> list[BodyParam]:
        ...
    @property
    def ret(self) -> TypeRefId | None:
        """
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def body(self) -> ExprId | None:
        ...
    @property
    def bounds(self) -> list[TypeBound]:
        """
        Its `where`, as a signature's (N78).
         for type TypeBound, see 'loupe.hir/signature.pyi'
        """
        ...
    def __eq__(self, __other: LocalFunc) -> bool:
        ...
    def __ne__(self, __other: LocalFunc) -> bool:
        ...
class Local:
    """
    A name a body declares.
    """
    def __init__(self, __name: str, __kind: LocalKind, *, lone: bool = ...):
        ...
    @property
    def name(self) -> str:
        ...
    @property
    def kind(self) -> LocalKind:
        ...
    @property
    def lone(self) -> bool:
        """
        Whether it is a pattern's lone name, a constructor if one has the name (N72), and then no local at all.
        """
        ...
    def __eq__(self, __other: Local) -> bool:
        ...
    def __ne__(self, __other: Local) -> bool:
        ...
class LocalId:
    """
    A name a body declares, by its place among the body's `locals`.
    """
    def __init__(self, __index: int):
        ...
    @property
    def index(self) -> int:
        ...
    def __eq__(self, __other: LocalId) -> bool:
        ...
    def __ne__(self, __other: LocalId) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    def __repr__(self) -> str:
        ...
class BodyParam:
    """
    A parameter: its name, `None` for `_`; its type, written in a lambda or a local function's signature; its default value.
    """
    def __init__(self, __local: LocalId | None, *, ty: TypeRefId | None = ..., defaultValue: ExprId | None = ..., isMember: bool = ..., passedBy: str | None = ...):
        """
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def local(self) -> LocalId | None:
        ...
    @property
    def ty(self) -> TypeRefId | None:
        """
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def defaultValue(self) -> ExprId | None:
        ...
    @property
    def isMember(self) -> bool:
        """
        Whether it is a member as well, a `let` or `var` of a primary constructor (N69).
        """
        ...
    @property
    def passedBy(self) -> str | None:
        """
        The name it is passed by, if by one: a local function's parameter after `!`.
        """
        ...
    def __eq__(self, __other: BodyParam) -> bool:
        ...
    def __ne__(self, __other: BodyParam) -> bool:
        ...
class PatId:
    """
    A pattern of a body, by its place among the body's `pats`.
    """
    def __init__(self, __index: int):
        ...
    @property
    def index(self) -> int:
        ...
    def __eq__(self, __other: PatId) -> bool:
        ...
    def __ne__(self, __other: PatId) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    def __repr__(self) -> str:
        ...
class ExprId:
    """
    An expression of a body, by its place among the body's `exprs`.
    """
    def __init__(self, __index: int):
        ...
    @property
    def index(self) -> int:
        ...
    def __eq__(self, __other: ExprId) -> bool:
        ...
    def __ne__(self, __other: ExprId) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    def __repr__(self) -> str:
        ...
class LocalKind:
    """
    What declares a local.
    """
    def __eq__(self, __other: LocalKind) -> bool:
        ...
    def __ne__(self, __other: LocalKind) -> bool:
        ...
    kind: Literal['ParamLocal', 'LambdaParamLocal', 'VarLocal', 'FuncLocal', 'PatLocal', 'CatchLocal', 'ResourceLocal']
    class ParamLocal(LocalKind):
        kind: Literal['ParamLocal'] = 'ParamLocal'
        def __init__(self):
            ...
    class LambdaParamLocal(LocalKind):
        kind: Literal['LambdaParamLocal'] = 'LambdaParamLocal'
        def __init__(self):
            ...
    class VarLocal(LocalKind):
        kind: Literal['VarLocal'] = 'VarLocal'
        def __init__(self):
            ...
    class FuncLocal(LocalKind):
        kind: Literal['FuncLocal'] = 'FuncLocal'
        def __init__(self):
            ...
    class PatLocal(LocalKind):
        kind: Literal['PatLocal'] = 'PatLocal'
        def __init__(self):
            ...
    class CatchLocal(LocalKind):
        kind: Literal['CatchLocal'] = 'CatchLocal'
        def __init__(self):
            ...
    class ResourceLocal(LocalKind):
        kind: Literal['ResourceLocal'] = 'ResourceLocal'
        def __init__(self):
            ...
class CallArg:
    """
    An argument of a call: the name it is passed by, if any; whether it is a trailing lambda, passed by the name of the last parameter if that is passed by name (cjc's `GetArgName`).
    """
    def __init__(self, __name: str | None, __expr: ExprId, *, isInout: bool = ..., isTrailing: bool = ...):
        ...
    @property
    def name(self) -> str | None:
        ...
    @property
    def expr(self) -> ExprId:
        ...
    @property
    def isInout(self) -> bool:
        ...
    @property
    def isTrailing(self) -> bool:
        ...
    def __eq__(self, __other: CallArg) -> bool:
        ...
    def __ne__(self, __other: CallArg) -> bool:
        ...
class MatchArm:
    """
    A `case`: its patterns and guard, or its condition; what it evaluates to.
    """
    def __init__(self, __pats: list[PatId], __guard: ExprId | None, __condition: ExprId | None, __body: ExprId):
        ...
    @property
    def pats(self) -> list[PatId]:
        ...
    @property
    def guard(self) -> ExprId | None:
        ...
    @property
    def condition(self) -> ExprId | None:
        ...
    @property
    def body(self) -> ExprId:
        ...
    def __eq__(self, __other: MatchArm) -> bool:
        ...
    def __ne__(self, __other: MatchArm) -> bool:
        ...
class Resource:
    """
    A try-with-resources binding with optional local and type IDs and its initializer expression.
    """
    def __init__(self, __local: LocalId | None, __ty: TypeRefId | None, __value: ExprId):
        """
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def local(self) -> LocalId | None:
        ...
    @property
    def ty(self) -> TypeRefId | None:
        """
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def value(self) -> ExprId:
        ...
    def __eq__(self, __other: Resource) -> bool:
        ...
    def __ne__(self, __other: Resource) -> bool:
        ...
class AttrArg:
    """
    What a macro on a declaration, std.unittest's, takes in its `[...]` as code (#191).
    """
    def __eq__(self, __other: AttrArg) -> bool:
        ...
    def __ne__(self, __other: AttrArg) -> bool:
        ...
    kind: Literal['DataArg', 'OptionArg', 'ValueArg', 'TypesArg']
    class DataArg(AttrArg):
        kind: Literal['DataArg'] = 'DataArg'
        def __init__(self, __p1: ExprId | None, __p2: ExprId):
            ...
        @property
        def field0(self) -> ExprId | None:
            ...
        @property
        def field1(self) -> ExprId:
            ...
        __match_args__ = ('field0', 'field1')
    class OptionArg(AttrArg):
        kind: Literal['OptionArg'] = 'OptionArg'
        def __init__(self, __p1: ExprId, __p2: ExprId):
            ...
        @property
        def field0(self) -> ExprId:
            ...
        @property
        def field1(self) -> ExprId:
            ...
        __match_args__ = ('field0', 'field1')
    class ValueArg(AttrArg):
        kind: Literal['ValueArg'] = 'ValueArg'
        def __init__(self, __p1: ExprId):
            ...
        @property
        def field0(self) -> ExprId:
            ...
        __match_args__ = ('field0')
    class TypesArg(AttrArg):
        kind: Literal['TypesArg'] = 'TypesArg'
        def __init__(self, __p1: TypeRefId, __p2: list[TypeRefId]):
            """
             for type TypeRefId, see 'loupe.hir/signature.pyi'
            """
            ...
        @property
        def field0(self) -> TypeRefId:
            ...
        @property
        def field1(self) -> list[TypeRefId]:
            ...
        __match_args__ = ('field0', 'field1')
class CatchArm:
    """
    A catch clause with its optional local binding, caught type-reference IDs and body expression.
    """
    def __init__(self, __local: LocalId | None, __types: list[TypeRefId], __body: ExprId):
        """
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def local(self) -> LocalId | None:
        ...
    @property
    def types(self) -> list[TypeRefId]:
        """
         for type TypeRefId, see 'loupe.hir/signature.pyi'
        """
        ...
    @property
    def body(self) -> ExprId:
        ...
    def __eq__(self, __other: CatchArm) -> bool:
        ...
    def __ne__(self, __other: CatchArm) -> bool:
        ...
class Expr:
    """
    An expression as a body writes it, rust-analyzer's `hir::Expr`: what it holds are other expressions, patterns and types of the same body. A name is not resolved yet; an operator is as written.
    """
    def __eq__(self, __other: Expr) -> bool:
        ...
    def __ne__(self, __other: Expr) -> bool:
        ...
    kind: Literal['MissingExpr', 'LitExpr', 'StrExpr', 'PathExpr', 'FieldExpr', 'CallExpr', 'IndexExpr', 'UnaryExpr', 'BinaryExpr', 'IsExpr', 'AsExpr', 'RangeExpr', 'PostfixExpr', 'AssignedExpr', 'TupleExpr', 'ArrayExpr', 'UnitExpr', 'IfExpr', 'LetExpr', 'MatchExpr', 'QuestMatchExpr', 'TryExpr', 'ForExpr', 'WhileExpr', 'DoWhileExpr', 'ThrowExpr', 'ReturnExpr', 'BreakExpr', 'ContinueExpr', 'SpawnExpr', 'SynchronizedExpr', 'UnsafeExpr', 'LambdaExpr', 'ThisExpr', 'SuperExpr', 'WildcardExpr', 'ConvExpr', 'PrimExpr', 'TypeExpr', 'LangExpr', 'BlockExpr', 'QuoteExpr', 'MacroExpr']
    class MissingExpr(Expr):
        kind: Literal['MissingExpr'] = 'MissingExpr'
        def __init__(self):
            ...
    class LitExpr(Expr):
        kind: Literal['LitExpr'] = 'LitExpr'
        def __init__(self, __p1: str):
            ...
        @property
        def field0(self) -> str:
            ...
        __match_args__ = ('field0')
    class StrExpr(Expr):
        kind: Literal['StrExpr'] = 'StrExpr'
        def __init__(self, __p1: list[ExprId]):
            ...
        @property
        def field0(self) -> list[ExprId]:
            ...
        __match_args__ = ('field0')
    class PathExpr(Expr):
        kind: Literal['PathExpr'] = 'PathExpr'
        def __init__(self, __p1: str, __p2: list[TypeRefId]):
            """
             for type TypeRefId, see 'loupe.hir/signature.pyi'
            """
            ...
        @property
        def field0(self) -> str:
            ...
        @property
        def field1(self) -> list[TypeRefId]:
            ...
        __match_args__ = ('field0', 'field1')
    class FieldExpr(Expr):
        kind: Literal['FieldExpr'] = 'FieldExpr'
        def __init__(self, __p1: ExprId, __p2: str, __p3: list[TypeRefId]):
            """
             for type TypeRefId, see 'loupe.hir/signature.pyi'
            """
            ...
        @property
        def field0(self) -> ExprId:
            ...
        @property
        def field1(self) -> str:
            ...
        @property
        def field2(self) -> list[TypeRefId]:
            ...
        __match_args__ = ('field0', 'field1', 'field2')
    class CallExpr(Expr):
        kind: Literal['CallExpr'] = 'CallExpr'
        def __init__(self, __p1: ExprId, __p2: list[CallArg]):
            ...
        @property
        def field0(self) -> ExprId:
            ...
        @property
        def field1(self) -> list[CallArg]:
            ...
        __match_args__ = ('field0', 'field1')
    class IndexExpr(Expr):
        kind: Literal['IndexExpr'] = 'IndexExpr'
        def __init__(self, __p1: ExprId, __p2: list[ExprId]):
            ...
        @property
        def field0(self) -> ExprId:
            ...
        @property
        def field1(self) -> list[ExprId]:
            ...
        __match_args__ = ('field0', 'field1')
    class UnaryExpr(Expr):
        kind: Literal['UnaryExpr'] = 'UnaryExpr'
        def __init__(self, __p1: str, __p2: ExprId):
            ...
        @property
        def field0(self) -> str:
            ...
        @property
        def field1(self) -> ExprId:
            ...
        __match_args__ = ('field0', 'field1')
    class BinaryExpr(Expr):
        kind: Literal['BinaryExpr'] = 'BinaryExpr'
        def __init__(self, __p1: str, __p2: ExprId, __p3: ExprId):
            ...
        @property
        def field0(self) -> str:
            ...
        @property
        def field1(self) -> ExprId:
            ...
        @property
        def field2(self) -> ExprId:
            ...
        __match_args__ = ('field0', 'field1', 'field2')
    class IsExpr(Expr):
        kind: Literal['IsExpr'] = 'IsExpr'
        def __init__(self, __p1: ExprId, __p2: TypeRefId):
            """
             for type TypeRefId, see 'loupe.hir/signature.pyi'
            """
            ...
        @property
        def field0(self) -> ExprId:
            ...
        @property
        def field1(self) -> TypeRefId:
            ...
        __match_args__ = ('field0', 'field1')
    class AsExpr(Expr):
        kind: Literal['AsExpr'] = 'AsExpr'
        def __init__(self, __p1: ExprId, __p2: TypeRefId):
            """
             for type TypeRefId, see 'loupe.hir/signature.pyi'
            """
            ...
        @property
        def field0(self) -> ExprId:
            ...
        @property
        def field1(self) -> TypeRefId:
            ...
        __match_args__ = ('field0', 'field1')
    class RangeExpr(Expr):
        kind: Literal['RangeExpr'] = 'RangeExpr'
        def __init__(self, __p1: ExprId | None, __p2: ExprId | None, __p3: ExprId | None, __p4: bool):
            ...
        @property
        def field0(self) -> ExprId | None:
            ...
        @property
        def field1(self) -> ExprId | None:
            ...
        @property
        def field2(self) -> ExprId | None:
            ...
        @property
        def field3(self) -> bool:
            ...
        __match_args__ = ('field0', 'field1', 'field2', 'field3')
    class PostfixExpr(Expr):
        kind: Literal['PostfixExpr'] = 'PostfixExpr'
        def __init__(self, __p1: ExprId, __p2: str, __p3: ExprId | None):
            ...
        @property
        def field0(self) -> ExprId:
            ...
        @property
        def field1(self) -> str:
            ...
        @property
        def field2(self) -> ExprId | None:
            ...
        __match_args__ = ('field0', 'field1', 'field2')
    class AssignedExpr(Expr):
        kind: Literal['AssignedExpr'] = 'AssignedExpr'
        def __init__(self, __p1: str, __p2: ExprId, __p3: ExprId):
            ...
        @property
        def field0(self) -> str:
            ...
        @property
        def field1(self) -> ExprId:
            ...
        @property
        def field2(self) -> ExprId:
            ...
        __match_args__ = ('field0', 'field1', 'field2')
    class TupleExpr(Expr):
        kind: Literal['TupleExpr'] = 'TupleExpr'
        def __init__(self, __p1: list[ExprId]):
            ...
        @property
        def field0(self) -> list[ExprId]:
            ...
        __match_args__ = ('field0')
    class ArrayExpr(Expr):
        kind: Literal['ArrayExpr'] = 'ArrayExpr'
        def __init__(self, __p1: list[ExprId]):
            ...
        @property
        def field0(self) -> list[ExprId]:
            ...
        __match_args__ = ('field0')
    class UnitExpr(Expr):
        kind: Literal['UnitExpr'] = 'UnitExpr'
        def __init__(self):
            ...
    class IfExpr(Expr):
        kind: Literal['IfExpr'] = 'IfExpr'
        def __init__(self, __p1: ExprId, __p2: ExprId, __p3: ExprId | None):
            ...
        @property
        def field0(self) -> ExprId:
            ...
        @property
        def field1(self) -> ExprId:
            ...
        @property
        def field2(self) -> ExprId | None:
            ...
        __match_args__ = ('field0', 'field1', 'field2')
    class LetExpr(Expr):
        kind: Literal['LetExpr'] = 'LetExpr'
        def __init__(self, __p1: list[PatId], __p2: ExprId):
            ...
        @property
        def field0(self) -> list[PatId]:
            ...
        @property
        def field1(self) -> ExprId:
            ...
        __match_args__ = ('field0', 'field1')
    class MatchExpr(Expr):
        kind: Literal['MatchExpr'] = 'MatchExpr'
        def __init__(self, __p1: ExprId | None, __p2: list[MatchArm]):
            ...
        @property
        def field0(self) -> ExprId | None:
            ...
        @property
        def field1(self) -> list[MatchArm]:
            ...
        __match_args__ = ('field0', 'field1')
    class QuestMatchExpr(Expr):
        kind: Literal['QuestMatchExpr'] = 'QuestMatchExpr'
        def __init__(self, __p1: ExprId, __p2: list[MatchArm]):
            ...
        @property
        def field0(self) -> ExprId:
            ...
        @property
        def field1(self) -> list[MatchArm]:
            ...
        __match_args__ = ('field0', 'field1')
    class TryExpr(Expr):
        kind: Literal['TryExpr'] = 'TryExpr'
        def __init__(self, __p1: list[Resource], __p2: ExprId, __p3: list[CatchArm], __p4: ExprId | None):
            ...
        @property
        def field0(self) -> list[Resource]:
            ...
        @property
        def field1(self) -> ExprId:
            ...
        @property
        def field2(self) -> list[CatchArm]:
            ...
        @property
        def field3(self) -> ExprId | None:
            ...
        __match_args__ = ('field0', 'field1', 'field2', 'field3')
    class ForExpr(Expr):
        kind: Literal['ForExpr'] = 'ForExpr'
        def __init__(self, __p1: PatId, __p2: ExprId, __p3: ExprId | None, __p4: ExprId):
            ...
        @property
        def field0(self) -> PatId:
            ...
        @property
        def field1(self) -> ExprId:
            ...
        @property
        def field2(self) -> ExprId | None:
            ...
        @property
        def field3(self) -> ExprId:
            ...
        __match_args__ = ('field0', 'field1', 'field2', 'field3')
    class WhileExpr(Expr):
        kind: Literal['WhileExpr'] = 'WhileExpr'
        def __init__(self, __p1: ExprId, __p2: ExprId):
            ...
        @property
        def field0(self) -> ExprId:
            ...
        @property
        def field1(self) -> ExprId:
            ...
        __match_args__ = ('field0', 'field1')
    class DoWhileExpr(Expr):
        kind: Literal['DoWhileExpr'] = 'DoWhileExpr'
        def __init__(self, __p1: ExprId, __p2: ExprId):
            ...
        @property
        def field0(self) -> ExprId:
            ...
        @property
        def field1(self) -> ExprId:
            ...
        __match_args__ = ('field0', 'field1')
    class ThrowExpr(Expr):
        kind: Literal['ThrowExpr'] = 'ThrowExpr'
        def __init__(self, __p1: ExprId):
            ...
        @property
        def field0(self) -> ExprId:
            ...
        __match_args__ = ('field0')
    class ReturnExpr(Expr):
        kind: Literal['ReturnExpr'] = 'ReturnExpr'
        def __init__(self, __p1: ExprId | None):
            ...
        @property
        def field0(self) -> ExprId | None:
            ...
        __match_args__ = ('field0')
    class BreakExpr(Expr):
        kind: Literal['BreakExpr'] = 'BreakExpr'
        def __init__(self):
            ...
    class ContinueExpr(Expr):
        kind: Literal['ContinueExpr'] = 'ContinueExpr'
        def __init__(self):
            ...
    class SpawnExpr(Expr):
        kind: Literal['SpawnExpr'] = 'SpawnExpr'
        def __init__(self, __p1: ExprId | None, __p2: ExprId):
            ...
        @property
        def field0(self) -> ExprId | None:
            ...
        @property
        def field1(self) -> ExprId:
            ...
        __match_args__ = ('field0', 'field1')
    class SynchronizedExpr(Expr):
        kind: Literal['SynchronizedExpr'] = 'SynchronizedExpr'
        def __init__(self, __p1: ExprId, __p2: ExprId):
            ...
        @property
        def field0(self) -> ExprId:
            ...
        @property
        def field1(self) -> ExprId:
            ...
        __match_args__ = ('field0', 'field1')
    class UnsafeExpr(Expr):
        kind: Literal['UnsafeExpr'] = 'UnsafeExpr'
        def __init__(self, __p1: ExprId):
            ...
        @property
        def field0(self) -> ExprId:
            ...
        __match_args__ = ('field0')
    class LambdaExpr(Expr):
        kind: Literal['LambdaExpr'] = 'LambdaExpr'
        def __init__(self, __p1: list[BodyParam], __p2: ExprId):
            ...
        @property
        def field0(self) -> list[BodyParam]:
            ...
        @property
        def field1(self) -> ExprId:
            ...
        __match_args__ = ('field0', 'field1')
    class ThisExpr(Expr):
        kind: Literal['ThisExpr'] = 'ThisExpr'
        def __init__(self):
            ...
    class SuperExpr(Expr):
        kind: Literal['SuperExpr'] = 'SuperExpr'
        def __init__(self):
            ...
    class WildcardExpr(Expr):
        kind: Literal['WildcardExpr'] = 'WildcardExpr'
        def __init__(self):
            ...
    class ConvExpr(Expr):
        kind: Literal['ConvExpr'] = 'ConvExpr'
        def __init__(self, __p1: str, __p2: ExprId):
            ...
        @property
        def field0(self) -> str:
            ...
        @property
        def field1(self) -> ExprId:
            ...
        __match_args__ = ('field0', 'field1')
    class PrimExpr(Expr):
        kind: Literal['PrimExpr'] = 'PrimExpr'
        def __init__(self, __p1: str):
            ...
        @property
        def field0(self) -> str:
            ...
        __match_args__ = ('field0')
    class TypeExpr(Expr):
        kind: Literal['TypeExpr'] = 'TypeExpr'
        def __init__(self, __p1: TypeRefId):
            """
             for type TypeRefId, see 'loupe.hir/signature.pyi'
            """
            ...
        @property
        def field0(self) -> TypeRefId:
            ...
        __match_args__ = ('field0')
    class LangExpr(Expr):
        kind: Literal['LangExpr'] = 'LangExpr'
        def __init__(self, __p1: LangItem):
            """
             for type LangItem, see 'loupe.hir/lang_items.pyi'
            """
            ...
        @property
        def field0(self) -> LangItem:
            ...
        __match_args__ = ('field0')
    class BlockExpr(Expr):
        kind: Literal['BlockExpr'] = 'BlockExpr'
        def __init__(self, __p1: list[Stmt]):
            ...
        @property
        def field0(self) -> list[Stmt]:
            ...
        __match_args__ = ('field0')
    class QuoteExpr(Expr):
        kind: Literal['QuoteExpr'] = 'QuoteExpr'
        def __init__(self, __p1: list[ExprId]):
            ...
        @property
        def field0(self) -> list[ExprId]:
            ...
        __match_args__ = ('field0')
    class MacroExpr(Expr):
        kind: Literal['MacroExpr'] = 'MacroExpr'
        def __init__(self, __p1: MacroCall):
            ...
        @property
        def field0(self) -> MacroCall:
            ...
        __match_args__ = ('field0')
