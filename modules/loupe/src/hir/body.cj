package loupe.hir

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.Expr as AstExpr
import cjsyntax.ast.Param as AstParam
import cjsyntax.ast.Stmt as AstStmt
import cjsyntax.ast.{
    AnyHasName,
    Arg,
    ArgList,
    Block,
    CatchClause,
    DataArg,
    Decl,
    ExprFile,
    GenericConstraint,
    Interpolation,
    LambdaExpr,
    MacroAttr,
    MacroExpandDecl,
    MacroExpandExpr,
    MatchCase,
    Name,
    NameRef,
    ParamList,
    PathSegment,
    Pattern,
    QuoteInterpolation,
    ResourceDecl,
    StmtsFile,
    Type,
    TypesArg,
    VarDecl,
    identText
}
import ginkgo.{Kind, SyntaxElement, SyntaxNodePtr}
import loupe.db.{AnalysisDatabase, MacroSeverity}
import loupe.syntax.parse
import py_interop.*
import py_interop.internal_macros.DerivePython

/**
 * An expression of a body, by its place among the body's `exprs`.
 */
@DerivePython
public struct ExprId <: Equatable<ExprId> & Hashable & ToString {
    public ExprId(public let index: Int64) {}

    public operator func ==(other: ExprId): Bool {
        index == other.index
    }

    public operator func !=(other: ExprId): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        hasher.write(index)
        hasher.finish()
    }

    public func toString(): String {
        "ExprId(index: ${index})"
    }
}

/**
 * A pattern of a body, by its place among the body's `pats`.
 */
@DerivePython
public struct PatId <: Equatable<PatId> & Hashable & ToString {
    public PatId(public let index: Int64) {}

    public operator func ==(other: PatId): Bool {
        index == other.index
    }

    public operator func !=(other: PatId): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        hasher.write(index)
        hasher.finish()
    }

    public func toString(): String {
        "PatId(index: ${index})"
    }
}

/**
 * A name a body declares, by its place among the body's `locals`.
 */
@DerivePython
public struct LocalId <: Equatable<LocalId> & Hashable & ToString {
    public LocalId(public let index: Int64) {}

    public operator func ==(other: LocalId): Bool {
        index == other.index
    }

    public operator func !=(other: LocalId): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        hasher.write(index)
        hasher.finish()
    }

    public func toString(): String {
        "LocalId(index: ${index})"
    }
}

/**
 * What declares a local.
 */
@DerivePython
public enum LocalKind <: Equatable<LocalKind> {
    /**
     * A parameter of the declaration, of a local function or of a property's setter.
     */
    | ParamLocal
    /**
     * A parameter of a lambda.
     */
    | LambdaParamLocal
    /**
     * A name of a `let` or `var`.
     */
    | VarLocal
    | FuncLocal
    /**
     * A name a pattern of a `case`, a `let … <-` or a `for` binds.
     */
    | PatLocal
    | CatchLocal
    | ResourceLocal

    public operator func ==(other: LocalKind): Bool {
        match ((this, other)) {
            case (LocalKind.ParamLocal, LocalKind.ParamLocal) => true
            case (LocalKind.LambdaParamLocal, LocalKind.LambdaParamLocal) => true
            case (LocalKind.VarLocal, LocalKind.VarLocal) => true
            case (LocalKind.FuncLocal, LocalKind.FuncLocal) => true
            case (LocalKind.PatLocal, LocalKind.PatLocal) => true
            case (LocalKind.CatchLocal, LocalKind.CatchLocal) => true
            case (LocalKind.ResourceLocal, LocalKind.ResourceLocal) => true
            case _ => false
        }
    }

    public operator func !=(other: LocalKind): Bool {
        !(this == other)
    }
}

/**
 * A name a body declares.
 */
@DerivePython
public struct Local <: Equatable<Local> {
    public Local(
        public let name: String,
        public let kind: LocalKind,
        /**
         * Whether it is a pattern's lone name, a constructor if one has the name (N72), and then no
         * local at all.
         */
        public let lone!: Bool = false
    ) {}

    public operator func ==(other: Local): Bool {
        name == other.name && kind == other.kind && lone == other.lone
    }

    public operator func !=(other: Local): Bool {
        !(this == other)
    }
}

/**
 * A parameter: its name, `None` for `_`; its type, written in a lambda or a local function's
 * signature; its default value.
 */
@DerivePython
public struct BodyParam <: Equatable<BodyParam> {
    public BodyParam(
        public let local: ?LocalId,
        public let ty!: ?TypeRefId = None,
        public let defaultValue!: ?ExprId = None,
        /**
         * Whether it is a member as well, a `let` or `var` of a primary constructor (N69).
         */
        public let isMember!: Bool = false,
        /**
         * The name it is passed by, if by one: a local function's parameter after `!`.
         */
        public let passedBy!: ?String = None
    ) {}

    public operator func ==(other: BodyParam): Bool {
        local == other.local && ty == other.ty && defaultValue == other.defaultValue &&
            isMember == other.isMember &&
            passedBy == other.passedBy
    }

    public operator func !=(other: BodyParam): Bool {
        !(this == other)
    }
}

/**
 * A function declared in a body: its name, a local of the scope after it (N60).
 */
@DerivePython
public struct LocalFunc <: Equatable<LocalFunc> {
    public LocalFunc(
        public let local: LocalId,
        public let generics: Array<String>,
        public let params: Array<BodyParam>,
        public let ret: ?TypeRefId,
        public let body: ?ExprId,
        /**
         * Its `where`, as a signature's (N78).
         */
        public let bounds!: Array<TypeBound> = []
    ) {}

    public operator func ==(other: LocalFunc): Bool {
        local == other.local && generics == other.generics && params == other.params &&
            ret == other.ret &&
            body == other.body &&
            bounds == other.bounds
    }

    public operator func !=(other: LocalFunc): Bool {
        !(this == other)
    }
}

@DerivePython
public enum Stmt <: Equatable<Stmt> {
    /**
     * `let`, `var` or `const`: the names its pattern binds, seen after it (N60, N61).
     */
    | LetStmt(PatId, ?TypeRefId, ?ExprId)
    | ExprStmt(ExprId)
    /**
     * A function, by its place among the body's `funcs`.
     */
    | FuncStmt(Int64)

    public operator func ==(other: Stmt): Bool {
        match ((this, other)) {
            case (Stmt.LetStmt(left0, left1, left2), Stmt.LetStmt(right0, right1, right2)) =>
                left0 == right0 && left1 == right1 && left2 == right2
            case (Stmt.ExprStmt(left0), Stmt.ExprStmt(right0)) => left0 == right0
            case (Stmt.FuncStmt(left0), Stmt.FuncStmt(right0)) => left0 == right0
            case _ => false
        }
    }

    public operator func !=(other: Stmt): Bool {
        !(this == other)
    }
}

/**
 * An argument of a call: the name it is passed by, if any; whether it is a trailing lambda, passed
 * by the name of the last parameter if that is passed by name (cjc's `GetArgName`).
 */
@DerivePython
public struct CallArg <: Equatable<CallArg> {
    public CallArg(
        public let name: ?String,
        public let expr: ExprId,
        public let isInout!: Bool = false,
        public let isTrailing!: Bool = false
    ) {}

    public operator func ==(other: CallArg): Bool {
        name == other.name && expr == other.expr && isInout == other.isInout &&
            isTrailing == other.isTrailing
    }

    public operator func !=(other: CallArg): Bool {
        !(this == other)
    }
}

/**
 * A `case`: its patterns and guard, or its condition; what it evaluates to.
 */
@DerivePython
public struct MatchArm <: Equatable<MatchArm> {
    public MatchArm(
        public let pats: Array<PatId>,
        public let guard: ?ExprId,
        public let condition: ?ExprId,
        public let body: ExprId
    ) {}

    public operator func ==(other: MatchArm): Bool {
        pats == other.pats && guard == other.guard && condition == other.condition &&
            body == other.body
    }

    public operator func !=(other: MatchArm): Bool {
        !(this == other)
    }
}

@DerivePython
public struct Resource <: Equatable<Resource> {
    public Resource(
        public let local: ?LocalId,
        public let ty: ?TypeRefId,
        public let value: ExprId
    ) {}

    public operator func ==(other: Resource): Bool {
        local == other.local && ty == other.ty && value == other.value
    }

    public operator func !=(other: Resource): Bool {
        !(this == other)
    }
}

@DerivePython
public struct CatchArm <: Equatable<CatchArm> {
    public CatchArm(
        public let local: ?LocalId,
        public let types: Array<TypeRefId>,
        public let body: ExprId
    ) {}

    public operator func ==(other: CatchArm): Bool {
        local == other.local && types == other.types && body == other.body
    }

    public operator func !=(other: CatchArm): Bool {
        !(this == other)
    }
}

/**
 * An expression as a body writes it, rust-analyzer's `hir::Expr`: what it holds are other
 * expressions, patterns and types of the same body. A name is not resolved yet; an operator is as
 * written.
 */
@DerivePython
public enum Expr <: Equatable<Expr> {
    /**
     * An expression the parser did not find.
     */
    | MissingExpr
    | LitExpr(String)
    /**
     * A string, its interpolations each a block.
     */
    | StrExpr(Array<ExprId>)
    /**
     * A name, and the type arguments after it.
     */
    | PathExpr(String, Array<TypeRefId>)
    /**
     * `a.b`: what `b` is, inference's (step 7).
     */
    | FieldExpr(ExprId, String, Array<TypeRefId>)
    /**
     * A call, a trailing lambda its last argument.
     */
    | CallExpr(ExprId, Array<CallArg>)
    | IndexExpr(ExprId, Array<ExprId>)
    | UnaryExpr(String, ExprId)
    /**
     * An operator between two, assignments included.
     */
    | BinaryExpr(String, ExprId, ExprId)
    | IsExpr(ExprId, TypeRefId)
    | AsExpr(ExprId, TypeRefId)
    /**
     * Its start, end and step, and whether it includes its end.
     */
    | RangeExpr(?ExprId, ?ExprId, ?ExprId, Bool)
    /**
     * `x++` or `x--`: its operand and operator, and of an `a[i]` what is assigned to it, an `AssignedExpr`.
     */
    | PostfixExpr(ExprId, String, ?ExprId)
    /**
     * What `a[i] op= v` and `a[i]++` assign to `a[i]`, as cjc desugars them into
     * `a.[](i, value: a.[](i) op v)` (#245): the operator, the place, and `v` or the `1` of `++`. Never
     * written: the place is the one of the assignment holding it, the right alone its own.
     */
    | AssignedExpr(String, ExprId, ExprId)
    | TupleExpr(Array<ExprId>)
    | ArrayExpr(Array<ExprId>)
    | UnitExpr
    /**
     * Its condition, then, else.
     */
    | IfExpr(ExprId, ExprId, ?ExprId)
    /**
     * `let p <- e` in a condition: its patterns bind for what follows it by `&&`, and the block
     * the condition is of (N62).
     */
    | LetExpr(Array<PatId>, ExprId)
    | MatchExpr(?ExprId, Array<MatchArm>)
    /**
     * The `match` an optional chain is desugared to, cjc's `MatchExpr` of `SugarKind::QUEST` (8g): `a?.b.c` is
     * `match (a) { case Some($v) => Some($v.b.c) case None => None }`, each `?` a `match` inside
     * the one of the `?` before it; an assignment `a?.b = x` or `a?.b++` is `$v.b = x`, `$v.b++` in
     * its first arm, `()` in its second.
     */
    | QuestMatchExpr(ExprId, Array<MatchArm>)
    | TryExpr(Array<Resource>, ExprId, Array<CatchArm>, ?ExprId)
    /**
     * Its pattern, what it iterates over, its guard, its body.
     */
    | ForExpr(PatId, ExprId, ?ExprId, ExprId)
    | WhileExpr(ExprId, ExprId)
    | DoWhileExpr(ExprId, ExprId)
    | ThrowExpr(ExprId)
    | ReturnExpr(?ExprId)
    | BreakExpr
    | ContinueExpr
    | SpawnExpr(?ExprId, ExprId)
    | SynchronizedExpr(ExprId, ExprId)
    | UnsafeExpr(ExprId)
    /**
     * Its parameters, and its body, a block.
     */
    | LambdaExpr(Array<BodyParam>, ExprId)
    | ThisExpr
    | SuperExpr
    | WildcardExpr
    /**
     * `Int64(x)`.
     */
    | ConvExpr(String, ExprId)
    /**
     * `Int64` before a `.`.
     */
    | PrimExpr(String)
    /**
     * A type spelling used as the callee of a built-in constructor, not a value by itself.
     */
    | TypeExpr(TypeRefId)
    /**
     * A declaration of `std.core` a desugaring names, whatever the scopes do: R1's `Path::LangItem`.
     */
    | LangExpr(LangItem)
    | BlockExpr(Array<Stmt>)
    /**
     * `quote(…)`: its tokens are what it builds, not code run here; an `std.ast.Tokens` (N136). Its interpolations,
     * `$(e)` and `$x`, are: values of the macro, as a string's are of the code around it (#195).
     */
    | QuoteExpr(Array<ExprId>)
    /**
     * A macro call: what it expands to is not known here.
     */
    | MacroExpr(MacroCall)

    public operator func ==(other: Expr): Bool {
        match ((this, other)) {
            case (Expr.MissingExpr, Expr.MissingExpr) => true
            case (Expr.LitExpr(left0), Expr.LitExpr(right0)) => left0 == right0
            case (Expr.StrExpr(left0), Expr.StrExpr(right0)) => left0 == right0
            case (Expr.PathExpr(left0, left1), Expr.PathExpr(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (Expr.FieldExpr(left0, left1, left2), Expr.FieldExpr(right0, right1, right2)) =>
                left0 == right0 && left1 == right1 && left2 == right2
            case (Expr.CallExpr(left0, left1), Expr.CallExpr(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (Expr.IndexExpr(left0, left1), Expr.IndexExpr(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (Expr.UnaryExpr(left0, left1), Expr.UnaryExpr(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (Expr.BinaryExpr(left0, left1, left2), Expr.BinaryExpr(right0, right1, right2)) =>
                left0 == right0 && left1 == right1 && left2 == right2
            case (Expr.IsExpr(left0, left1), Expr.IsExpr(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (Expr.AsExpr(left0, left1), Expr.AsExpr(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (
                    Expr.RangeExpr(left0, left1, left2, left3),
                    Expr.RangeExpr(right0, right1, right2, right3)
                ) => left0 == right0 && left1 == right1 && left2 == right2 && left3 == right3
            case (
                    Expr.PostfixExpr(left0, left1, left2),
                    Expr.PostfixExpr(right0, right1, right2)
                ) => left0 == right0 && left1 == right1 && left2 == right2
            case (
                    Expr.AssignedExpr(left0, left1, left2),
                    Expr.AssignedExpr(right0, right1, right2)
                ) => left0 == right0 && left1 == right1 && left2 == right2
            case (Expr.TupleExpr(left0), Expr.TupleExpr(right0)) => left0 == right0
            case (Expr.ArrayExpr(left0), Expr.ArrayExpr(right0)) => left0 == right0
            case (Expr.UnitExpr, Expr.UnitExpr) => true
            case (Expr.IfExpr(left0, left1, left2), Expr.IfExpr(right0, right1, right2)) =>
                left0 == right0 && left1 == right1 && left2 == right2
            case (Expr.LetExpr(left0, left1), Expr.LetExpr(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (Expr.MatchExpr(left0, left1), Expr.MatchExpr(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (Expr.QuestMatchExpr(left0, left1), Expr.QuestMatchExpr(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (
                    Expr.TryExpr(left0, left1, left2, left3),
                    Expr.TryExpr(right0, right1, right2, right3)
                ) => left0 == right0 && left1 == right1 && left2 == right2 && left3 == right3
            case (
                    Expr.ForExpr(left0, left1, left2, left3),
                    Expr.ForExpr(right0, right1, right2, right3)
                ) => left0 == right0 && left1 == right1 && left2 == right2 && left3 == right3
            case (Expr.WhileExpr(left0, left1), Expr.WhileExpr(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (Expr.DoWhileExpr(left0, left1), Expr.DoWhileExpr(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (Expr.ThrowExpr(left0), Expr.ThrowExpr(right0)) => left0 == right0
            case (Expr.ReturnExpr(left0), Expr.ReturnExpr(right0)) => left0 == right0
            case (Expr.BreakExpr, Expr.BreakExpr) => true
            case (Expr.ContinueExpr, Expr.ContinueExpr) => true
            case (Expr.SpawnExpr(left0, left1), Expr.SpawnExpr(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (Expr.SynchronizedExpr(left0, left1), Expr.SynchronizedExpr(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (Expr.UnsafeExpr(left0), Expr.UnsafeExpr(right0)) => left0 == right0
            case (Expr.LambdaExpr(left0, left1), Expr.LambdaExpr(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (Expr.ThisExpr, Expr.ThisExpr) => true
            case (Expr.SuperExpr, Expr.SuperExpr) => true
            case (Expr.WildcardExpr, Expr.WildcardExpr) => true
            case (Expr.ConvExpr(left0, left1), Expr.ConvExpr(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (Expr.PrimExpr(left0), Expr.PrimExpr(right0)) => left0 == right0
            case (Expr.TypeExpr(left0), Expr.TypeExpr(right0)) => left0 == right0
            case (Expr.LangExpr(left0), Expr.LangExpr(right0)) => left0 == right0
            case (Expr.BlockExpr(left0), Expr.BlockExpr(right0)) => left0 == right0
            case (Expr.QuoteExpr(left0), Expr.QuoteExpr(right0)) => left0 == right0
            case (Expr.MacroExpr(left0), Expr.MacroExpr(right0)) => left0 == right0
            case _ => false
        }
    }

    public operator func !=(other: Expr): Bool {
        !(this == other)
    }
}

/**
 * A macro called in a body, `@M[a](b, c)`: the path it names, the macro outermost of those nested
 * (`@A @B(x)`); the types its `[…]` lists, if it has one, each an identifier, those between `|`
 * (`@AssertThrows[A | B]`, N136), none of one of anything else; its arguments when they parse as
 * an argument list, the innermost's, lowered so the names in them resolve: the macro sees them as
 * tokens all the same.
 */
@DerivePython
public struct MacroCall <: Equatable<MacroCall> {
    public MacroCall(
        public let path: Array<String>,
        public let attr: ?Array<TypeRefId>,
        public let args: Array<CallArg>
    ) {}

    public operator func ==(other: MacroCall): Bool {
        path == other.path && attr == other.attr && args == other.args
    }

    public operator func !=(other: MacroCall): Bool {
        !(this == other)
    }
}

/**
 * What a macro on a declaration, std.unittest's, takes in its `[...]` as code (#191).
 */
@DerivePython
public enum AttrArg <: Equatable<AttrArg> {
    /**
     * `x in src` of `@Test`, `@TestCase`, `@Bench`, `@Strategy`: `x`, a name in the scope of the declaration's
     * parameters, none for `config.x`; `src`, an expression in the scope around them.
     */
    | DataArg(?ExprId, ExprId)
    /**
     * `k: v` of `@Configure`: `KeyK.k`, the option `k` names, and `v`.
     */
    | OptionArg(ExprId, ExprId)
    /**
     * `@Timeout[e]`, `@Measure[a, b]`: an expression.
     */
    | ValueArg(ExprId)
    /**
     * `T in <A, B>` of `@Types`: the type parameter, and the types it is run with.
     */
    | TypesArg(TypeRefId, Array<TypeRefId>)

    public operator func ==(other: AttrArg): Bool {
        match ((this, other)) {
            case (AttrArg.DataArg(left0, left1), AttrArg.DataArg(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (AttrArg.OptionArg(left0, left1), AttrArg.OptionArg(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (AttrArg.ValueArg(left0), AttrArg.ValueArg(right0)) => left0 == right0
            case (AttrArg.TypesArg(left0, left1), AttrArg.TypesArg(right0, right1)) =>
                left0 == right0 && left1 == right1
            case _ => false
        }
    }

    public operator func !=(other: AttrArg): Bool {
        !(this == other)
    }
}

/**
 * A macro on a declaration that takes code in its `[...]`, by the name it is called by: the path it names, and
 * the arguments, those of std.unittest's macros. Whether it is std's is inference's to find.
 */
@DerivePython
public struct DeclAttr <: Equatable<DeclAttr> {
    public DeclAttr(public let path: Array<String>, public let args: Array<AttrArg>) {}

    public operator func ==(other: DeclAttr): Bool {
        path == other.path && args == other.args
    }

    public operator func !=(other: DeclAttr): Bool {
        !(this == other)
    }
}

/**
 * The macros on a declaration whose `[...]` is code by their name, as std.unittest's (#191): what
 * `@Tag` and `@Skip` list is none, nor is a user's macro's.
 */
let CODE_ATTRS =
    HashSet<String>(
        ["Test", "TestCase", "Bench", "Strategy", "Configure", "Timeout", "Measure", "Types"]
    )

/**
 * A pattern as a body writes it.
 */
@DerivePython
public enum Pat <: Equatable<Pat> {
    | MissingPat
    | WildcardPat
    | LitPat(String)
    /**
     * A name: a binding, or, a lone one, a constructor (N72).
     */
    | BindPat(LocalId)
    /**
     * `n: T`, `_: T`.
     */
    | TypePat(?LocalId, TypeRefId)
    | TuplePat(Array<PatId>)
    /**
     * `E.A(p)`, `A(p)`: the path to the constructor, and the patterns of its arguments.
     */
    | EnumPat(Array<String>, Array<PatId>)

    public operator func ==(other: Pat): Bool {
        match ((this, other)) {
            case (Pat.MissingPat, Pat.MissingPat) => true
            case (Pat.WildcardPat, Pat.WildcardPat) => true
            case (Pat.LitPat(left0), Pat.LitPat(right0)) => left0 == right0
            case (Pat.BindPat(left0), Pat.BindPat(right0)) => left0 == right0
            case (Pat.TypePat(left0, left1), Pat.TypePat(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (Pat.TuplePat(left0), Pat.TuplePat(right0)) => left0 == right0
            case (Pat.EnumPat(left0, left1), Pat.EnumPat(right0, right1)) =>
                left0 == right0 && left1 == right1
            case _ => false
        }
    }

    public operator func !=(other: Pat): Bool {
        !(this == other)
    }
}

/**
 * The declaration's identity for evaluating annotation arguments before its bindings enter scope.
 */
@Derive[Equatable, Hashable]
enum AnnotationOwner {
    | AnnotatedPattern(PatId)
    /**
     * A local function by its index in Body.funcs.
     */
    | AnnotatedFunction(Int64)
}

/**
 * A possible custom annotation on a local declaration; resolution distinguishes it from a macro.
 * Its type is public because it appears in Body's public constructor; its data stays HIR-local.
 */
@DerivePython
public struct LocalAnnotation <: Equatable<LocalAnnotation> {
    @PyIgnore
    LocalAnnotation(
        let path: Array<String>,
        let args: Array<CallArg>,
        /**
         * Synthetic constructor callee; the declaration range lives in BodySourceMap.annotations.
         */
        let target: ExprId,
        let owner: AnnotationOwner,
        /**
         * Enclosing declaration wrappers, outermost first, to keep real macro input opaque.
         */
        let wrappers: Array<Array<String>>
    ) {}

    public operator func ==(other: LocalAnnotation): Bool {
        path == other.path && args == other.args && target == other.target &&
            owner == other.owner &&
            wrappers == other.wrappers
    }

    public operator func !=(other: LocalAnnotation): Bool {
        !(this == other)
    }
}

/**
 * What a declaration's body is lowered to, nothing of where it is written: rust-analyzer's `Body`.
 * An edit that does not change its code, a blank line or a comment, an edit elsewhere in the file,
 * leaves it equal.
 */
@DerivePython
public struct Body <: Equatable<Body> {
    public Body(
        public let exprs!: Array<Expr> = [],
        public let pats!: Array<Pat> = [],
        public let locals!: Array<Local> = [],
        public let funcs!: Array<LocalFunc> = [],
        /**
         * The types it writes, as a signature's (D48).
         */
        public let types!: Array<TypeRef> = [],
        /**
         * The declaration's parameters, their default values in the body (N67).
         */
        public let params!: Array<BodyParam> = [],
        /**
         * A function's block, a variable's initializer.
         */
        public let value!: ?ExprId = None,
        /**
         * A property's `get` and `set`, each a lambda.
         */
        public let accessors!: Array<ExprId> = [],
        /**
         * What the macros on it take as code in their `[...]`, outermost first.
         */
        public let attrs!: Array<DeclAttr> = [],
        /**
         * Possible custom annotations; constructor typing decides whether placement can be checked.
         */
        let annotations!: Array<LocalAnnotation> = []
    ) {}

    public operator func [](id: ExprId): Expr {
        exprs[id.index]
    }

    public operator func [](id: PatId): Pat {
        pats[id.index]
    }

    public operator func [](id: LocalId): Local {
        locals[id.index]
    }

    /**
     * Its types as a signature, for `Signature.text`.
     */
    public func typesAsSignature(): Signature {
        Signature(types: types)
    }

    public operator func ==(other: Body): Bool {
        exprs == other.exprs && pats == other.pats && locals == other.locals &&
            funcs == other.funcs &&
            types == other.types &&
            params == other.params &&
            value == other.value &&
            accessors == other.accessors &&
            attrs == other.attrs
    }

    public operator func !=(other: Body): Bool {
        !(this == other)
    }
}

/**
 * A node of a body, qualified by the expression expansion it came from. `None` is the body's own file.
 * Offsets and kinds alone do not identify a node once several expansions are lowered into one body.
 */
@Derive[Equatable, Hashable]
public struct BodySource {
    public BodySource(
        public let ptr: SyntaxNodePtr<SyntaxKind>,
        public let expansion!: ?MacroCallId = None
    ) {}

    /**
     * The file containing this node, relative to the body's own file `owner`.
     */
    public func inFile(owner: ItemFile): ItemFile {
        expansion.map { call => ItemFile.Expansion(call) } ?? owner
    }

    /**
     * Resolves in the current tree; `None` if that file or node is no longer available.
     */
    public func node(db: AnalysisDatabase, owner: ItemFile): ?CjSyntaxNode {
        let (root, _) = syntaxOf(db, inFile(owner)) ?? return None
        ptr.tryToNode(root)
    }
}

/**
 * A body node's origin: syntax in a file, or a synthetic node introduced by lowering.
 * A missing array index is separate from a present synthetic node.
 */
@DerivePython
public enum BodyOrigin <: Equatable<BodyOrigin> {
    | WrittenSource(BodySource)
    | SyntheticSource

    /**
     * The syntax source, when lowering preserved one.
     */
    public prop written: ?BodySource {
        get() {
            match (this) {
                case WrittenSource(source) => source
                case SyntheticSource => None
            }
        }
    }

    public operator func ==(other: BodyOrigin): Bool {
        match ((this, other)) {
            case (BodyOrigin.WrittenSource(left0), BodyOrigin.WrittenSource(right0)) =>
                left0 == right0
            case (BodyOrigin.SyntheticSource, BodyOrigin.SyntheticSource) => true
            case _ => false
        }
    }

    public operator func !=(other: BodyOrigin): Bool {
        !(this == other)
    }
}

@Derive[Equatable]
struct ExprSourceAlias {
    ExprSourceAlias(let source: BodySource, let expr: ExprId) {}
}

/**
 * The declaration targeted by a possible custom annotation, apart from its synthetic callee.
 */
@Derive[Equatable]
protected struct AnnotationSource {
    protected AnnotationSource(protected let anchor: ExprId, protected let source: BodySource) {}
}

/**
 * Where each expression, pattern, local and type of a body is written: a local by its name; and the
 * other way round, by hash, for what asks of every name of a file.
 */
@DerivePython
public struct BodySourceMap <: Equatable<BodySourceMap> {
    public let exprs: Array<BodyOrigin>
    public let pats: Array<BodyOrigin>
    public let locals: Array<BodyOrigin>
    public let types: Array<BodyOrigin>
    /**
     * Placement targets kept separate from their synthetic constructor callee expressions.
     */
    @PyIgnore
    protected let annotations: Array<AnnotationSource>
    private let aliases: Array<ExprSourceAlias>
    private let exprIndex: BodySourceIndex
    private let patIndex: BodySourceIndex
    private let localIndex: BodySourceIndex
    private let typeIndex: BodySourceIndex

    @PyIgnore
    init(
        exprs!: Array<BodyOrigin> = [],
        pats!: Array<BodyOrigin> = [],
        locals!: Array<BodyOrigin> = [],
        types!: Array<BodyOrigin> = [],
        annotations!: Array<AnnotationSource> = [],
        aliases!: Array<ExprSourceAlias> = []
    ) {
        this.exprs = exprs
        this.pats = pats
        this.locals = locals
        this.types = types
        this.annotations = annotations
        this.aliases = aliases
        exprIndex = BodySourceIndex(exprs)
        for (alias in aliases) {
            exprIndex.alias(alias.source, alias.expr.index)
        }
        patIndex = BodySourceIndex(pats)
        localIndex = BodySourceIndex(locals)
        typeIndex = BodySourceIndex(types)
    }

    /**
     * The expression of the node `ptr` as written: of a node desugared, the first of those of the
     * node, the `match`es it is desugared into after it (A29). An unqualified pointer belongs to the body's own
     * file; use `exprAtSource` for a node from an expression expansion.
     */
    @PyIgnore
    public func exprAt(ptr: SyntaxNodePtr<SyntaxKind>): ?ExprId {
        exprAtSource(BodySource(ptr))
    }

    /**
     * The expression at the file-qualified syntax source.
     */
    public func exprAtSource(source: BodySource): ?ExprId {
        match (exprIndex.get(source)) {
            case Some(i) => ExprId(i)
            case None => None
        }
    }

    @PyIgnore
    public func patAt(ptr: SyntaxNodePtr<SyntaxKind>): ?PatId {
        patAtSource(BodySource(ptr))
    }

    /**
     * The pattern at the file-qualified syntax source.
     */
    public func patAtSource(source: BodySource): ?PatId {
        match (patIndex.get(source)) {
            case Some(i) => PatId(i)
            case None => None
        }
    }

    /**
     * The local whose name `ptr` points to.
     */
    @PyIgnore
    public func localAt(ptr: SyntaxNodePtr<SyntaxKind>): ?LocalId {
        localAtSource(BodySource(ptr))
    }

    /**
     * The local declaration at the file-qualified syntax source.
     */
    public func localAtSource(source: BodySource): ?LocalId {
        match (localIndex.get(source)) {
            case Some(i) => LocalId(i)
            case None => None
        }
    }

    @PyIgnore
    public func typeAt(ptr: SyntaxNodePtr<SyntaxKind>): ?TypeRefId {
        typeAtSource(BodySource(ptr))
    }

    /**
     * The type reference at the file-qualified syntax source.
     */
    public func typeAtSource(source: BodySource): ?TypeRefId {
        match (typeIndex.get(source)) {
            case Some(i) => TypeRefId(i)
            case None => None
        }
    }

    /**
     * Field by field, but the indexes, which the arrays make.
     */
    public operator func ==(other: BodySourceMap): Bool {
        exprs == other.exprs && pats == other.pats && locals == other.locals &&
            types == other.types &&
            annotations == other.annotations &&
            aliases == other.aliases
    }

    public operator func !=(other: BodySourceMap): Bool {
        !(this == other)
    }
}

/**
 * The first index of each pointer of an array.
 */
class BodySourceIndex {
    private let first: HashMap<BodySource, Int64>

    init(origins: Array<BodyOrigin>) {
        first = HashMap<BodySource, Int64>(origins.size)
        for (i in 0..origins.size) {
            if (let WrittenSource(source) <- origins[i] && !first.contains(source)) {
                first.add(source, i)
            }
        }
    }

    func alias(source: BodySource, index: Int64): Unit {
        first[source] = index
    }

    func get(source: BodySource): ?Int64 {
        first.get(source)
    }
}

@DerivePython
public struct LoweredBody <: Equatable<LoweredBody> {
    public LoweredBody(public let body: Body, public let sourceMap: BodySourceMap) {}

    public operator func ==(other: LoweredBody): Bool {
        body == other.body && sourceMap == other.sourceMap
    }

    public operator func !=(other: LoweredBody): Bool {
        !(this == other)
    }
}

/**
 * The `LoweredBody` of `def`: of its node in a source file, or in an output of the macro server (D132), whose spans
 * say where it comes from; an empty one for a declaration with no body, of a package compiled already, of an expansion
 * cjls writes itself, whose bodies are comments (D118), or no longer there.
 */
@CalcaTracked
public func bodyWithSourceMap(db: AnalysisDatabase, def: DefId): LoweredBody {
    let (root, ids, file) =
        match (def.file(db)) {
            case Source(file) => (parse(db, file).syntaxNode(), itemIdMap(db, file), file)
            case Expansion(call) where !macroExpansion(db, call).spans.isEmpty() =>
                (expansionParse(db, call).syntaxNode(), expansionIdMap(db, call), call.file(db))
            case _ => return LoweredBody(Body(), BodySourceMap())
        }
    match (ids.node(def.item(db), root).flatMap { node => Decl.cast(node) }) {
        case Some(decl) =>
            let expansions = HashMap<SyntaxNodePtr<SyntaxKind>, MacroCallId>()
            if (let Source(_) <- def.file(db) && file.macroOutputs(db).size > 0) {
                for (
                    request in macroRequests(db, file) where request.current &&
                        request.call.inBody(db).isSome() &&
                        request.call.item(db) == def.item(db)
                ) {
                    let output = macroOutputOf(db, request.call) ?? continue
                    if (
                        output.expansion.isNone() ||
                            output
                                .diagnostics
                                .any { one => one.severity == MacroSeverity.MacroError }
                    ) {
                        continue
                    }
                    let node = bodyCallNodeOf(db, request.call) ?? continue
                    expansions[SyntaxNodePtr(node)] = request.call
                }
            }
            lowerBodyWith(
                decl,
                ActiveFilter.of(db, file),
                {
                    node =>
                    let call = expansions.get(SyntaxNodePtr(node)) ?? return None
                    let parsed = expansionParse(db, call)
                    if (!parsed.errors.isEmpty()) {
                        return None
                    }
                    (call, parsed.syntaxNode())
                }
            )
        case None => LoweredBody(Body(), BodySourceMap())
    }
}

/**
 * The `Body` of `def`. An edit of the file but of its code leaves it equal, and what read it is not
 * run again.
 */
@CalcaTracked
public func body(db: AnalysisDatabase, def: DefId): Body {
    bodyWithSourceMap(db, def).body
}

/**
 * The body of `decl`, what `active` leaves out of the build left out: parameters, declarations of
 * its blocks, accessors. This standalone lowering reads no expansion answers, including for speculative completion.
 */
public func lowerBody(decl: Decl, active!: ActiveFilter = ALL_ACTIVE): LoweredBody {
    lowerBodyWith(decl, active, { _ => None })
}

private func lowerBodyWith(
    decl: Decl,
    active: ActiveFilter,
    expansion: (CjSyntaxNode) -> ?(MacroCallId, CjSyntaxNode)
): LoweredBody {
    let lowering = BodyLowering(active, expansion)
    var params = Array<BodyParam>()
    var value: ?ExprId = None
    var accessors = Array<ExprId>()
    match (decl) {
        case Decl.AsFuncDecl(it) =>
            (params, value) = (lowering.params(it.paramLists()), lowering.blockOf(it.block()))
        case Decl.AsMainDecl(it) =>
            (params, value) = (lowering.params(it.paramLists()), lowering.blockOf(it.block()))
        case Decl.AsMacroDecl(it) =>
            (params, value) = (lowering.params(it.paramLists()), lowering.blockOf(it.block()))
        case Decl.AsInitDecl(it) =>
            (params, value) = (lowering.params(it.paramLists()), lowering.blockOf(it.block()))
        case Decl.AsFinalizerDecl(it) => value = lowering.blockOf(it.block())
        case Decl.AsPrimaryInitDecl(it) =>
            (params, value) =
                (lowering.params(it.paramLists(), primary: true), lowering.blockOf(it.block()))
        case Decl.AsVarDecl(it) => value = it.expr().map { one => lowering.expr(one) }
        case Decl.AsPropDecl(it) =>
            if (let Some(propBody) <- it.propBody()) {
                accessors =
                    propBody.propAccessors() |>
                        filter { accessor => active.isActive(accessor.syntax) } |>
                        map {
                            accessor =>
                            let accessorParams = lowering.params(accessor.paramLists())
                            lowering
                                .add(
                                    Expr
                                        .LambdaExpr(
                                            accessorParams,
                                            lowering.block(accessor.block())
                                        ),
                                    accessor.syntax
                                )
                        } |>
                        collectArray
            }
        case _ => ()
    }
    lowering.finish(params, value, accessors, attrs: lowering.declAttrs(decl))
}

/**
 * One body as it is lowered: its arrays and where each element is written.
 */
class BodyLowering {
    let active: ActiveFilter
    let types: SignatureLowering
    let exprs = ArrayList<Expr>()
    let exprOrigins = ArrayList<BodyOrigin>()
    let pats = ArrayList<Pat>()
    let patOrigins = ArrayList<BodyOrigin>()
    let locals = ArrayList<Local>()
    let localOrigins = ArrayList<BodyOrigin>()
    let funcs = ArrayList<LocalFunc>()
    let annotations = ArrayList<LocalAnnotation>()
    let annotationSources = ArrayList<AnnotationSource>()
    private let aliases = ArrayList<ExprSourceAlias>()
    // the `?`s of the optional chains being lowered, innermost last: what each is applied to, and the
    // local its value is bound to
    private let quests = ArrayList<(ExprId, LocalId)>()

    private let expansion: (CjSyntaxNode) -> ?(MacroCallId, CjSyntaxNode)
    private var currentExpansion: ?MacroCallId = None
    private let typeExpansions = HashMap<Int64, MacroCallId>()

    init(active: ActiveFilter, expansion: (CjSyntaxNode) -> ?(MacroCallId, CjSyntaxNode)) {
        this.expansion = expansion
        this.active = active
        this.types = SignatureLowering(active: active)
    }

    func finish(
        params: Array<BodyParam>,
        value: ?ExprId,
        accessors: Array<ExprId>,
        attrs!: Array<DeclAttr> = []
    ): LoweredBody {
        LoweredBody(
            Body(
                exprs: exprs.toArray(),
                pats: pats.toArray(),
                locals: locals.toArray(),
                funcs: funcs.toArray(),
                types: types.types.toArray(),
                params: params,
                value: value,
                accessors: accessors,
                attrs: attrs,
                annotations: annotations.toArray()
            ),
            BodySourceMap(
                exprs: exprOrigins.toArray(),
                pats: patOrigins.toArray(),
                locals: localOrigins.toArray(),
                types: Array(types.ptrs.size) {
                    i =>
                    match (types.ptrs[i]) {
                        case Some(ptr) =>
                            WrittenSource(BodySource(ptr, expansion: typeExpansions.get(i)))
                        case None => SyntheticSource
                    }
                },
                annotations: annotationSources.toArray(),
                aliases: aliases.toArray()
            )
        )
    }

    /**
     * The parameters of every list in order; a `let` or `var` one of a primary constructor a member
     * as well.
     */
    func params(lists: Iterator<ParamList>, primary!: Bool = false): Array<BodyParam> {
        let lowered = ArrayList<BodyParam>()
        for (list in lists) {
            for (param in list.writtenParams() where active.isActive(param.syntax)) {
                lowered.add(paramOf(param, primary))
            }
        }
        lowered.toArray()
    }

    private func paramOf(param: AstParam, primary: Bool): BodyParam {
        // the default value first: it sees the parameters before this one, not this one (N67)
        let defaultValue = param.expr().map { one => expr(one) }
        let passedBy: ?String =
            if (param.bangToken().isSome()) { param.name()?.text() } else { None }
        BodyParam(
            local(param.name(), LocalKind.ParamLocal),
            ty: param.ty().map { one => types.lower(one) },
            defaultValue: defaultValue,
            isMember: primary && (param.letToken().isSome() || param.varToken().isSome()),
            passedBy: passedBy
        )
    }

    func local(name: ?Name, kind: LocalKind, lone!: Bool = false): ?LocalId {
        let one = name ?? return None
        locals.add(Local(one.text(), kind, lone: lone))
        localOrigins.add(WrittenSource(source(one.syntax)))
        LocalId(locals.size - 1)
    }

    private func source(node: CjSyntaxNode): BodySource {
        BodySource(SyntaxNodePtr(node), expansion: currentExpansion)
    }

    /**
     * Lower in place; a statement expansion must not introduce an extra lexical scope.
     */
    private func inExpansion<T>(call: MacroCallId, lower: () -> T): T {
        let previous = currentExpansion
        let start = types.ptrs.size
        currentExpansion = call
        try {
            lower()
        } finally {
            for (i in start..types.ptrs.size) {
                typeExpansions[i] = call
            }
            currentExpansion = previous
        }
    }

    private func expansionOf(node: CjSyntaxNode): ?(MacroCallId, CjSyntaxNode) {
        // Output-written calls have no source call key; recursive expansion is a separate feature.
        if (currentExpansion.isSome()) {
            return None
        }
        expansion(node)
    }

    func add(expr: Expr, node: CjSyntaxNode): ExprId {
        exprs.add(expr)
        exprOrigins.add(WrittenSource(source(node)))
        ExprId(exprs.size - 1)
    }

    private func missing(): ExprId {
        exprs.add(Expr.MissingExpr)
        exprOrigins.add(SyntheticSource)
        ExprId(exprs.size - 1)
    }

    func blockOf(node: ?Block): ?ExprId {
        node.map { one => block(one) }
    }

    func block(node: ?Block): ExprId {
        match (node) {
            case Some(one) => add(Expr.BlockExpr(stmts(one.stmts())), one.syntax)
            case None => missing()
        }
    }

    func stmts(nodes: Iterator<AstStmt>): Array<Stmt> {
        let lowered = ArrayList<Stmt>()
        for (node in nodes) {
            let syntax =
                match (node) {
                    case AstStmt.ExprStmt(one) => one.syntax
                    case AstStmt.DeclStmt(one) => one.syntax
                }
            if (
                active.isActive(syntax) && let Some((call, root)) <- expansionOf(syntax) &&
                    let Some(file) <- StmtsFile.cast(root)
            ) {
                let statements = inExpansion(call, { => stmts(file.stmts()) })
                if (let Some(Stmt.ExprStmt(id)) <- statements.get(statements.size - 1)) {
                    aliases.add(ExprSourceAlias(source(syntax), id))
                }
                lowered.add(all: statements)
                continue
            }
            match (node) {
                case AstStmt.ExprStmt(one) => lowered.add(Stmt.ExprStmt(expr(one)))
                case AstStmt.DeclStmt(decl) where !active.isActive(decl.syntax) => ()
                case AstStmt.DeclStmt(decl) =>
                    if (let Some(one) <- stmtOf(decl)) {
                        lowered.add(one)
                    }
            }
        }
        lowered.toArray()
    }

    /**
     * A declaration in a block: a variable, or a function; nothing for a type, which a body does not
     * have (N65).
     */
    private func stmtOf(decl: Decl): ?Stmt {
        match (decl) {
            case Decl.AsVarDecl(it) =>
                // the initializer first: it does not see the names it is bound to (N61)
                let value = it.expr().map { one => expr(one) }
                let ty = it.ty().map { one => types.lower(one) }
                let pat =
                    match ((it.name(), it.pattern())) {
                        case (Some(name), _) =>
                            addPat(
                                Pat.BindPat(local(name, LocalKind.VarLocal).getOrThrow()),
                                name.syntax
                            )
                        case (None, Some(pattern)) => pat(pattern, LocalKind.VarLocal, lone: false)
                        case (None, None) => addPat(Pat.MissingPat, None)
                    }
                Stmt.LetStmt(pat, ty, value)
            case Decl.AsFuncDecl(it) =>
                let name = local(it.name(), LocalKind.FuncLocal) ?? return None
                let generics =
                    match (it.typeParamList()) {
                        case Some(list) =>
                            list.typeParams() |> map { param => param.name()?.text() ?? "" } |>
                                collectArray
                        case None => Array<String>()
                    }
                let params = params(it.paramLists())
                let ret = it.retType().flatMap { one => one.ty() }.map { one => types.lower(one) }
                let bounds =
                    match (it.whereClause()) {
                        case Some(clause) =>
                            clause.genericConstraints() |>
                                map {
                                    constraint: GenericConstraint =>
                                    TypeBound(
                                        types.lower(constraint.ty()),
                                        types.bounds(constraint.typeBoundList())
                                    )
                                } |>
                                collectArray
                        case None => Array<TypeBound>()
                    }
                funcs
                    .add(
                        LocalFunc(name, generics, params, ret, blockOf(it.block()), bounds: bounds)
                    )
                Stmt.FuncStmt(funcs.size - 1)
            case Decl.AsMacroExpandDecl(it) =>
                let inner = it.decl() ?? return None
                let statement = stmtOf(inner)
                match (statement) {
                    case Some(Stmt.LetStmt(pattern, _, _)) =>
                        recordLocalAnnotation(it, inner.syntax, AnnotatedPattern(pattern))
                    case Some(Stmt.FuncStmt(index)) =>
                        recordLocalAnnotation(it, inner.syntax, AnnotatedFunction(index))
                    case _ => ()
                }
                statement
            case _ => None
        }
    }

    private func recordLocalAnnotation(
        call: MacroExpandDecl,
        declaration: CjSyntaxNode,
        owner: AnnotationOwner
    ): Unit {
        var target = declaration
        while (
            let Some(inner) <- MacroExpandDecl.cast(target).flatMap { nested => nested.decl() }
        ) {
            target = inner.syntax
        }
        let named = AnyHasName.cast(target)?.name()?.syntax
        let sourceNode =
            if (named.isSome()) { named } else { VarDecl.cast(target)?.pattern()?.syntax }
        let node = sourceNode ?? return
        let path = call.nameRefs() |> map { name: NameRef => name.text() } |> collectArray
        let arguments = annotationArguments(call) ?? return
        let anchor = missing()
        annotationSources.add(AnnotationSource(anchor, source(node)))
        let wrappers = ArrayList<Array<String>>()
        var wrapped = call.syntax
        while (let Some(parent) <- wrapped.parent && parent.kind == SyntaxKind.MacroExpandDecl) {
            wrapped = parent
        }
        while (let Some(one) <- MacroExpandDecl.cast(wrapped)) {
            wrappers.add(one.nameRefs() |> map { name: NameRef => name.text() } |> collectArray)
            wrapped = one.decl()?.syntax ?? break
        }
        annotations.add(LocalAnnotation(path, arguments, anchor, owner, wrappers.toArray()))
    }

    private func annotationArguments(call: MacroExpandDecl): ?Array<CallArg> {
        let arguments = ArrayList<CallArg>()
        if (let Some(attr) <- call.macroAttr()) {
            for (element in attr.syntax.childrenWithTokens()) {
                match (element) {
                    case SyntaxElement.Node(child) where child.kind != SyntaxKind.Arg => return None
                    case SyntaxElement.Token(token) where !token.kind.isTrivia() &&
                            ![SyntaxKind.LBracket, SyntaxKind.RBracket, SyntaxKind.Comma]
                                .contains(token.kind) => return None
                    case _ => ()
                }
            }
            for (child in attr.syntax.children()) {
                let arg = Arg.cast(child) ?? return None
                arguments
                    .add(
                        CallArg(
                            arg.nameRef()?.text(),
                            exprOf(arg.expr()),
                            isInout: arg.inoutToken().isSome()
                        )
                    )
            }
        }
        Some(arguments.toArray())
    }

    /**
     * The expression `node`; an optional chain that ends at it desugared (8g).
     */
    func expr(node: AstExpr): ExprId {
        let mark = quests.size
        let id = link(node)
        if (quests.size == mark) { id } else { questMatches(id, mark, node) }
    }

    /**
     * `node`, an optional chain that ends there yet to be desugared: the `match`es of its `?`s,
     * from the innermost out, around `value` (cjc's `DesugarOptionalChainExpr`).
     */
    private func questMatches(value: ExprId, mark: Int64, node: AstExpr): ExprId {
        let assigns =
            match (node) {
                case AstExpr.AsBinExpr(it) => ASSIGNMENTS.contains(it.op()?.text() ?? "")
                case AstExpr.AsPostfixExpr(_) => true
                case _ => false
            }
        var inner =
            if (assigns) {
                value
            } else {
                synthesized(
                    Expr
                        .CallExpr(
                            synthesized(Expr.LangExpr(LangItem.OptionSome)),
                            [CallArg(None, value)]
                        )
                )
            }
        while (quests.size > mark) {
            // read before removed: -O2 miscompiles one taken apart straight from `remove`
            let (selector, local) = quests[quests.size - 1]
            quests.remove(at: quests.size - 1)
            let some = addPat(Pat.EnumPat(["Some"], [addPat(Pat.BindPat(local), None)]), None)
            let none = addPat(Pat.EnumPat(["None"], []), None)
            let otherwise =
                if (assigns) {
                    synthesized(Expr.UnitExpr)
                } else {
                    synthesized(Expr.LangExpr(LangItem.OptionNone))
                }
            // after the chain's own: an expression is found by its node as written (`exprAt`)
            inner =
                add(
                    Expr
                        .QuestMatchExpr(
                            selector,
                            [
                                MatchArm([some], None, None, inner),
                                MatchArm([none], None, None, otherwise)
                            ]
                        ),
                    node.syntax
                )
        }
        inner
    }

    private func synthesized(expr: Expr): ExprId {
        exprs.add(expr)
        exprOrigins.add(SyntheticSource)
        ExprId(exprs.size - 1)
    }

    /**
     * `node`, a link of an optional chain if it is one, the chain not desugared yet: what its
     * left is, a link of its own, the `?`s of what it applies to are those of the chain.
     */
    private func link(node: AstExpr): ExprId {
        if (
            let Some((call, root)) <- expansionOf(node.syntax) &&
                let Some(value) <- ExprFile.cast(root).flatMap { one => one.expr() }
        ) {
            let id = inExpansion(call, { => expr(value) })
            aliases.add(ExprSourceAlias(source(node.syntax), id))
            return id
        }
        let lowered =
            match (node) {
                case AstExpr.AsLiteral(it) => Expr.LitExpr(it.value()?.text() ?? "")
                // of one character, a `Rune` or a `Byte` where one is expected: a literal as a number is
                case AstExpr.AsStringLit(it) where isOneChar(it.syntax.text()) =>
                    Expr.LitExpr(it.syntax.text())
                case AstExpr.AsStringLit(it) =>
                    Expr
                        .StrExpr(
                            it.interpolations() |>
                                map {
                                    one: Interpolation =>
                                    add(Expr.BlockExpr(stmts(one.stmts())), one.syntax)
                                } |>
                                collectArray
                        )
                case AstExpr.AsRefExpr(it) =>
                    Expr.PathExpr(it.nameRef()?.text() ?? "", typeArgs(it.typeArgList()?.types()))
                case AstExpr.AsMemberAccessExpr(it) =>
                    Expr
                        .FieldExpr(
                            linkOf(it.receiver()),
                            it.nameRef()?.text() ?? "",
                            typeArgs(it.typeArgList()?.types())
                        )
                case AstExpr.AsCallExpr(it) =>
                    Expr.CallExpr(linkOf(it.callee()), args(it.argList()))
                case AstExpr.AsTrailingLambdaExpr(it) =>
                    let callee = linkOf(it.callee())
                    let lambda = lambdaOf(it.lambda())
                    match (this.exprs[callee.index]) {
                        // `f(a) {…}` is `f(a, {…})`, one call of the whole node: `f(a)` no expression of its own
                        case Expr.CallExpr(inner, args) =>
                            this.exprs[callee.index] =
                                Expr
                                    .CallExpr(
                                        inner,
                                        args.concat([CallArg(None, lambda, isTrailing: true)])
                                    )
                            exprOrigins[callee.index] = WrittenSource(source(it.syntax))
                            return callee
                        case _ => Expr.CallExpr(callee, [CallArg(None, lambda, isTrailing: true)])
                    }
                case AstExpr.AsIndexExpr(it) =>
                    Expr
                        .IndexExpr(
                            linkOf(it.base()),
                            it.indices() |> map { one => expr(one) } |> collectArray
                        )
                // `a?`: `$v`, bound to the value of `a` by the `match` the chain is desugared to
                case AstExpr.AsOptionalExpr(it) =>
                    let selector = linkOf(it.expr())
                    locals.add(Local("$v", LocalKind.PatLocal))
                    localOrigins.add(SyntheticSource)
                    quests.add((selector, LocalId(locals.size - 1)))
                    Expr.PathExpr("$v", [])
                case AstExpr.AsUnaryExpr(it) =>
                    Expr.UnaryExpr(it.op()?.text() ?? "", exprOf(it.expr()))
                case AstExpr.AsBinExpr(it) =>
                    let op = it.op()?.text() ?? ""
                    // an assignment's left a link: `a?.b = x` is a chain (cjc's `ParseExprWithRightExprOrType`)
                    if (ASSIGNMENTS.contains(op)) {
                        let lhs = linkOf(it.lhs())
                        let rhs = exprOf(it.rhs())
                        // `a[i] op= v` assigns `a[i] op v` (#245)
                        match (this.exprs[lhs.index]) {
                            case Expr.IndexExpr(_, _) where op != "=" =>
                                Expr
                                    .BinaryExpr(
                                        op,
                                        lhs,
                                        synthesized(Expr.AssignedExpr(op[0..op.size - 1], lhs, rhs))
                                    )
                            case _ => Expr.BinaryExpr(op, lhs, rhs)
                        }
                    } else {
                        Expr.BinaryExpr(op, exprOf(it.lhs()), exprOf(it.rhs()))
                    }
                case AstExpr.AsIsExpr(it) => Expr.IsExpr(exprOf(it.expr()), types.lower(it.ty()))
                case AstExpr.AsAsExpr(it) => Expr.AsExpr(exprOf(it.expr()), types.lower(it.ty()))
                case AstExpr.AsRangeExpr(it) =>
                    Expr
                        .RangeExpr(
                            it.start().map { one => expr(one) },
                            it.end().map { one => expr(one) },
                            it.step().map { one => expr(one) },
                            it.op()?.kind == SyntaxKind.DotDotEq
                        )
                case AstExpr.AsPostfixExpr(it) =>
                    let op = it.op()?.text() ?? ""
                    let inner = linkOf(it.expr())
                    // `a[i]++` is `a[i] += 1` (#245)
                    let value =
                        match (this.exprs[inner.index]) {
                            case Expr.IndexExpr(_, _) =>
                                let one = synthesized(Expr.LitExpr("1"))
                                Some(
                                    synthesized(
                                        Expr
                                            .AssignedExpr(
                                                if (op == "--") { "-" } else { "+" },
                                                inner,
                                                one
                                            )
                                    )
                                )
                            case _ => None<ExprId>
                        }
                    Expr.PostfixExpr(inner, op, value)
                case AstExpr.AsParenExpr(it) => return exprOf(it.expr())
                case AstExpr.AsTupleExpr(it) =>
                    Expr.TupleExpr(it.exprs() |> map { one => expr(one) } |> collectArray)
                case AstExpr.AsArrayExpr(it) =>
                    Expr.ArrayExpr(it.exprs() |> map { one => expr(one) } |> collectArray)
                case AstExpr.AsUnitExpr(_) => Expr.UnitExpr
                case AstExpr.AsIfExpr(it) =>
                    let condition = exprOf(it.condition())
                    let then = block(it.then())
                    let otherwise =
                        match ((it.elseBlock(), it.elseIf())) {
                            case (Some(one), _) => Some(block(one))
                            case (None, Some(one)) => Some(expr(AstExpr.AsIfExpr(one)))
                            case (None, None) => None<ExprId>
                        }
                    Expr.IfExpr(condition, then, otherwise)
                case AstExpr.AsLetExpr(it) =>
                    // what it matches first: it does not see the names it binds
                    let value = exprOf(it.expr())
                    Expr
                        .LetExpr(
                            it.patterns() |>
                                map { one => pat(one, LocalKind.PatLocal, lone: true) } |>
                                collectArray,
                            value
                        )
                case AstExpr.AsMatchExpr(it) =>
                    let scrutinee = it.expr().map { one => expr(one) }
                    let arms =
                        match (it.matchBody()) {
                            case Some(matchBody) =>
                                matchBody.matchCases() |> map { one: MatchCase => arm(one) } |>
                                    collectArray
                            case None => Array<MatchArm>()
                        }
                    Expr.MatchExpr(scrutinee, arms)
                case AstExpr.AsTryExpr(it) =>
                    let resources =
                        match (it.resourceList()) {
                            case Some(list) =>
                                list.resourceDecls() |>
                                    map { one: ResourceDecl => resource(one) } |>
                                    collectArray
                            case None => Array<Resource>()
                        }
                    let tried = block(it.block())
                    let catches =
                        it.catchClauses() |> map { one: CatchClause => catchArm(one) } |>
                            collectArray
                    Expr
                        .TryExpr(
                            resources,
                            tried,
                            catches,
                            it.finallyClause().map { one => block(one.block()) }
                        )
                case AstExpr.AsForInExpr(it) =>
                    let iterated = exprOf(it.expr())
                    let pattern =
                        match (it.pattern()) {
                            case Some(one) => pat(one, LocalKind.PatLocal, lone: true)
                            case None => addPat(Pat.MissingPat, None)
                        }
                    Expr
                        .ForExpr(
                            pattern,
                            iterated,
                            it.guard().flatMap { one => one.expr() }.map { one => expr(one) },
                            block(it.block())
                        )
                case AstExpr.AsWhileExpr(it) => Expr.WhileExpr(exprOf(it.expr()), block(it.block()))
                case AstExpr.AsDoWhileExpr(it) =>
                    let body = block(it.block())
                    Expr.DoWhileExpr(body, exprOf(it.expr()))
                case AstExpr.AsThrowExpr(it) => Expr.ThrowExpr(exprOf(it.expr()))
                case AstExpr.AsReturnExpr(it) => Expr.ReturnExpr(it.expr().map { one => expr(one) })
                case AstExpr.AsBreakExpr(_) => Expr.BreakExpr
                case AstExpr.AsContinueExpr(_) => Expr.ContinueExpr
                case AstExpr.AsSpawnExpr(it) =>
                    let context = it.context().map { one => expr(one) }
                    let lambda =
                        it.syntax.children() |>
                            filterMap { child: CjSyntaxNode => LambdaExpr.cast(child) } |>
                            first
                    Expr.SpawnExpr(context, lambdaOf(lambda))
                case AstExpr.AsSynchronizedExpr(it) =>
                    Expr.SynchronizedExpr(exprOf(it.expr()), block(it.block()))
                case AstExpr.AsUnsafeExpr(it) => Expr.UnsafeExpr(block(it.block()))
                case AstExpr.AsLambdaExpr(it) => return lambdaOf(it)
                case AstExpr.AsThisExpr(_) => Expr.ThisExpr
                case AstExpr.AsSuperExpr(_) => Expr.SuperExpr
                case AstExpr.AsWildcardExpr(_) => Expr.WildcardExpr
                case AstExpr.AsTypeConvExpr(it) =>
                    Expr.ConvExpr(it.primType()?.keyword()?.text() ?? "", exprOf(it.expr()))
                case AstExpr.AsPrimTypeExpr(it) => Expr.PrimExpr(it.keyword()?.text() ?? "")
                case AstExpr.AsVArrayExpr(it) =>
                    let ty = types.lower(it.vArrayType().map { one => Type.AsVArrayType(one) })
                    // The call owns the written node; its type keeps the original type source map.
                    Expr.CallExpr(synthesized(Expr.TypeExpr(ty)), args(it.argList()))
                case AstExpr.AsQuoteExpr(it) =>
                    Expr
                        .QuoteExpr(
                            it.quoteInterpolations() |>
                                map { one: QuoteInterpolation => exprOf(one.expr()) } |>
                                collectArray
                        )
                // no arguments: a macro call on a declaration (`var f = @M func g() {}`) is given the declaration, not
                // values
                case AstExpr.AsMacroExpandDecl(it) =>
                    Expr.MacroExpr(MacroCall(macroName(it).split("."), None, []))
                case AstExpr.AsMacroExpandExpr(it) =>
                    let path = it.nameRefs() |> map { name: NameRef => name.text() } |> collectArray
                    Expr
                        .MacroExpr(
                            MacroCall(
                                path,
                                it.macroAttr().map { attr => attrTypes(attr) },
                                macroArgs(it)
                            )
                        )
            }
        add(lowered, node.syntax)
    }

    private func exprOf(node: ?AstExpr): ExprId {
        match (node) {
            case Some(one) => expr(one)
            case None => missing()
        }
    }

    private func linkOf(node: ?AstExpr): ExprId {
        match (node) {
            case Some(one) => link(one)
            case None => missing()
        }
    }

    private func typeArgs(nodes: ?Iterator<Type>): Array<TypeRefId> {
        match (nodes) {
            case Some(it) => it |> map { one: Type => types.lower(one) } |> collectArray
            case None => Array<TypeRefId>()
        }
    }

    /**
     * The types `attr`, a macro call's `[…]`, lists: identifiers between `|`; none if it holds anything else.
     */
    private func attrTypes(attr: MacroAttr): Array<TypeRefId> {
        let tokens = ArrayList<CjSyntaxToken>()
        for (element in attr.syntax.descendantsWithTokens()) {
            if (
                let SyntaxElement.Token(token) <- element && !token.kind.isTrivia() &&
                    token.kind != SyntaxKind.LBracket &&
                    token.kind != SyntaxKind.RBracket
            ) {
                tokens.add(token)
            }
        }
        // `A`, `A | B`: an identifier at each even place, a `|` at each odd one
        for (i in 0..tokens.size) {
            let wanted = if (i % 2 == 0) { SyntaxKind.Ident } else { SyntaxKind.Pipe }
            if (tokens[i].kind != wanted) {
                return []
            }
        }
        if (tokens.size % 2 == 0) {
            return []
        }
        tokens
            .toArray()
            .filter { token => token.kind == SyntaxKind.Ident }
            .map { token => types.named(identText(token)) }
    }

    /**
     * What the macros on `decl`, the calls around it, take as code in their `[...]`, those of `CODE_ATTRS`, outermost
     * first.
     */
    func declAttrs(decl: Decl): Array<DeclAttr> {
        let calls = ArrayList<MacroExpandDecl>()
        var node = decl.syntax.parent
        while (let Some(one) <- node && let Some(call) <- MacroExpandDecl.cast(one)) {
            calls.add(call)
            node = one.parent
        }
        calls.reverse()
        let found = ArrayList<DeclAttr>()
        for (call in calls) {
            let path = call.nameRefs() |> map { name: NameRef => name.text() } |> collectArray
            let attr = call.macroAttr() ?? continue
            if (CODE_ATTRS.contains(path.get(path.size - 1) ?? "")) {
                found.add(DeclAttr(path, attrArgs(attr)))
            }
        }
        found.toArray()
    }

    /**
     * The arguments of `attr` as they parsed: `x in src`, `T in <A, B>`, `k: v`, an expression; none if it stayed
     * tokens.
     */
    private func attrArgs(attr: MacroAttr): Array<AttrArg> {
        let found = ArrayList<AttrArg>()
        for (child in attr.syntax.children()) {
            if (let Some(it) <- DataArg.cast(child)) {
                let param =
                    match (it.param()) {
                        case Some(one) where one.syntax.kind == SyntaxKind.RefExpr =>
                            Some(expr(one))
                        case _ => None<ExprId>
                    }
                found.add(AttrArg.DataArg(param, exprOf(it.source())))
            } else if (let Some(it) <- TypesArg.cast(child)) {
                let param = types.lower(it.ty())
                found.add(AttrArg.TypesArg(param, typeArgs(it.typeArgList()?.types())))
            } else if (let Some(it) <- Arg.cast(child)) {
                match (it.nameRef()) {
                    case Some(name) =>
                        found.add(AttrArg.OptionArg(optionKey(name.text(), it), exprOf(it.expr())))
                    case None => found.add(AttrArg.ValueArg(exprOf(it.expr())))
                }
            }
        }
        found.toArray()
    }

    /**
     * `KeyK.k`, what `k: v` of `@Configure` sets, as std.unittest's `createOptionFQName` writes it: the access at
     * `arg`, where `k` is.
     */
    private func optionKey(name: String, arg: Arg): ExprId {
        let runes = name.toRuneArray()
        let key = "Key${String(runes[..1]).toAsciiUpper()}${String(runes[1..])}"
        exprs.add(Expr.PathExpr(key, []))
        exprOrigins.add(SyntheticSource)
        add(Expr.FieldExpr(ExprId(exprs.size - 1), name, []), arg.syntax)
    }

    /**
     * `@M(a, b)`'s arguments, of the innermost call when `@A[x] @M(a, b)` nests them.
     */
    private func macroArgs(node: MacroExpandExpr): Array<CallArg> {
        match (node.macroArgs()) {
            case Some(it) => args(it.argList())
            case None => node.macroExpandExpr().map { inner => macroArgs(inner) } ?? []
        }
    }

    private func args(list: ?ArgList): Array<CallArg> {
        let it = list?.args() ?? return []
        it |>
            map {
                arg: Arg =>
                CallArg(
                    arg.nameRef()?.text(),
                    exprOf(arg.expr()),
                    isInout: arg.inoutToken().isSome()
                )
            } |>
            collectArray
    }

    /**
     * A lambda: its parameters, then its statements, a block of its own.
     */
    private func lambdaOf(node: ?LambdaExpr): ExprId {
        let it = node ?? return missing()
        let params =
            match (it.lambdaParamList()) {
                case Some(list) =>
                    list.lambdaParams() |>
                        map {
                            param =>
                            BodyParam(
                                local(param.name(), LocalKind.LambdaParamLocal),
                                ty: param.ty().map { one => types.lower(one) }
                            )
                        } |>
                        collectArray
                case None => Array<BodyParam>()
            }
        // the block has no node of its own: the lambda's is the lambda's
        exprs.add(Expr.BlockExpr(stmts(it.stmts())))
        exprOrigins.add(SyntheticSource)
        add(Expr.LambdaExpr(params, ExprId(exprs.size - 1)), it.syntax)
    }

    private func arm(node: MatchCase): MatchArm {
        let pats =
            node.patterns() |> map { one => pat(one, LocalKind.PatLocal, lone: true) } |>
                collectArray
        let guard = node.guard().flatMap { one => one.expr() }.map { one => expr(one) }
        let condition = node.condition().map { one => expr(one) }
        let body = add(Expr.BlockExpr(stmts(node.stmts())), node.syntax)
        MatchArm(pats, guard, condition, body)
    }

    private func resource(node: ResourceDecl): Resource {
        let value = exprOf(node.expr())
        let ty = node.ty().map { one => types.lower(one) }
        Resource(local(node.name(), LocalKind.ResourceLocal), ty, value)
    }

    private func catchArm(node: CatchClause): CatchArm {
        let (local, caught) =
            match (node.catchPat()) {
                case Some(catchPat) =>
                    (
                        local(catchPat.name(), LocalKind.CatchLocal),
                        catchPat.types() |> map { one: Type => types.lower(one) } |> collectArray
                    )
                case None => (None<LocalId>, Array<TypeRefId>())
            }
        CatchArm(local, caught, block(node.block()))
    }

    /**
     * The pattern `node`, its names locals of `kind`; a lone name may be a constructor if `lone`.
     */
    func pat(node: Pattern, kind: LocalKind, lone!: Bool): PatId {
        let lowered =
            match (node) {
                case Pattern.AsWildcardPat(_) => Pat.WildcardPat
                case Pattern.AsLiteralPat(it) => Pat.LitPat(compactText(it.syntax))
                case Pattern.AsBindPat(it) =>
                    match (local(it.name(), kind, lone: lone)) {
                        case Some(one) => Pat.BindPat(one)
                        case None => Pat.MissingPat
                    }
                case Pattern.AsTypePat(it) =>
                    Pat.TypePat(local(it.name(), kind), types.lower(it.ty()))
                case Pattern.AsTuplePat(it) =>
                    Pat
                        .TuplePat(
                            it.patterns() |> map { one => pat(one, kind, lone: lone) } |>
                                collectArray
                        )
                case Pattern.AsEnumPat(it) =>
                    Pat
                        .EnumPat(
                            it.pathSegments() |>
                                map { segment: PathSegment => segment.nameRef()?.text() ?? "" } |>
                                collectArray,
                            it.patterns() |> map { one => pat(one, kind, lone: lone) } |>
                                collectArray
                        )
            }
        addPat(lowered, node.syntax)
    }

    private func addPat(pat: Pat, node: ?CjSyntaxNode): PatId {
        pats.add(pat)
        patOrigins.add(node.map { one => WrittenSource(source(one)) } ?? SyntheticSource)
        PatId(pats.size - 1)
    }
}
