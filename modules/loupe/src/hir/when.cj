package loupe.hir

import std.collection.*
import std.convert.Parsable
import calca.*
import calca.macros.*
import cjsyntax.CjSyntaxNode
import cjsyntax.ast.Annotation as AnnotationNode
import cjsyntax.ast.Expr as AstExpr
import cjsyntax.ast.{AnyHasAnnotations, BinExpr, RefExpr, StringLit}
import ginkgo.TextRange
import loupe.db.{AnalysisDatabase, Cfg, SourceFile}
import loupe.syntax.parse
import py_interop.*
import py_interop.internal_macros.DerivePython

const CJC_VERSION = "cjc_version"

/**
 * The value of `debug` and `test` in a `Cfg` when they are set.
 */
public const FLAG_SET: String = "true"

/**
 * The condition of a `@When`, lowered from its expression with nothing of the tree: what cjc
 * evaluates it as (`src/ConditionalCompilation`). One cjc rejects is `CfgInvalid`, false as cjc
 * evaluates it, unlike R1's `CfgExpr::Invalid`, which is active (#149, D93).
 */
@DerivePython
public enum CfgExpr <: Equatable<CfgExpr> {
    // `key op "value"`, `op` as written: `==`, `!=`, `<`, `<=`, `>`, `>=`
    | CfgCompare(String, String, String)
    // `debug` or `test`, `true` under a `!`
    | CfgFlag(String, Bool)
    | CfgAnd(CfgExpr, CfgExpr)
    | CfgOr(CfgExpr, CfgExpr)
    | CfgInvalid

    /**
     * Whether it holds under `cfg`; `None` when that cannot be told, a condition `cfg` has no value
     * of. One cjc rejects is false, as cjc has it. `&&` and `||` are Kleene's: unknown only when the
     * side known does not decide.
     */
    public func evaluate(cfg: Cfg): ?Bool {
        match (this) {
            case CfgCompare(key, op, value) =>
                let actual = cfg.get(key) ?? return None
                let order =
                    if (key == CJC_VERSION) {
                        compareVersions(actual, value) ?? return None
                    } else {
                        actual.compare(value)
                    }
                Some(holds(op, order))
            case CfgFlag(name, negated) => Some(((cfg.get(name) ?? "") == FLAG_SET) != negated)
            case CfgAnd(left, right) =>
                match ((left.evaluate(cfg), right.evaluate(cfg))) {
                    case (Some(false), _) | (_, Some(false)) => Some(false)
                    case (Some(true), Some(true)) => Some(true)
                    case _ => None
                }
            case CfgOr(left, right) =>
                match ((left.evaluate(cfg), right.evaluate(cfg))) {
                    case (Some(true), _) | (_, Some(true)) => Some(true)
                    case (Some(false), Some(false)) => Some(false)
                    case _ => None
                }
            case CfgInvalid => Some(false)
        }
    }

    /**
     * Whether code under it is in the build `cfg` makes: unless it is known to be false.
     */
    public func isActive(cfg: Cfg): Bool {
        evaluate(cfg) != Some(false)
    }

    /**
     * Why it is false under `cfg`: what each condition making it so is instead, each once,
     * `os is "Linux"`, `test is not set`. Empty unless it is false.
     */
    public func whyFalse(cfg: Cfg): Array<String> {
        let reasons = ArrayList<String>()
        collectWhyFalse(cfg, reasons)
        reasons.toArray()
    }

    private func collectWhyFalse(cfg: Cfg, reasons: ArrayList<String>): Unit {
        if (evaluate(cfg) != Some(false)) {
            return
        }
        let reason =
            match (this) {
                case CfgCompare(key, _, _) => "${key} is \"${cfg.get(key) ?? ""}\""
                case CfgFlag(name, true) => "${name} is set"
                case CfgFlag(name, false) => "${name} is not set"
                case CfgAnd(left, right) =>
                    left.collectWhyFalse(cfg, reasons)
                    right.collectWhyFalse(cfg, reasons)
                    return
                case CfgOr(left, right) =>
                    left.collectWhyFalse(cfg, reasons)
                    right.collectWhyFalse(cfg, reasons)
                    return
                case CfgInvalid => return
            }
        if (!reasons.contains(reason)) {
            reasons.add(reason)
        }
    }

    public operator func ==(other: CfgExpr): Bool {
        match ((this, other)) {
            case (
                    CfgExpr.CfgCompare(left0, left1, left2),
                    CfgExpr.CfgCompare(right0, right1, right2)
                ) => left0 == right0 && left1 == right1 && left2 == right2
            case (CfgExpr.CfgFlag(left0, left1), CfgExpr.CfgFlag(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (CfgExpr.CfgAnd(left0, left1), CfgExpr.CfgAnd(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (CfgExpr.CfgOr(left0, left1), CfgExpr.CfgOr(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (CfgExpr.CfgInvalid, CfgExpr.CfgInvalid) => true
            case _ => false
        }
    }

    public operator func !=(other: CfgExpr): Bool {
        !(this == other)
    }
}

/**
 * The conditions cjc knows, and the operators each takes: `debug` and `test` none, they are flags.
 */
let BUILTIN_OPS: Array<(String, Array<String>)> =
    [
        ("backend", ["==", "!="]),
        ("arch", ["==", "!="]),
        ("os", ["==", "!="]),
        (CJC_VERSION, ["==", "!=", "<", "<=", ">", ">="]),
        ("debug", []),
        ("test", []),
        ("env", ["==", "!="])
    ]

/**
 * The values cjc takes of the conditions it knows all values of.
 */
let BUILTIN_VALUES: Array<(String, Array<String>)> =
    [
        ("backend", ["cjnative"]),
        ("arch", ["x86_64", "aarch64", "arm"]),
        ("os", ["Windows", "Linux", "macOS", "iOS"]),
        ("env", ["", "gnu", "ohos", "simulator", "android"])
    ]

const INVALID_EXPR = "conditional compilation not support this expression"

private func builtinOps(key: String): ?Array<String> {
    for ((name, ops) in BUILTIN_OPS where name == key) {
        return ops
    }
    None
}

private func builtinValues(key: String): ?Array<String> {
    for ((name, values) in BUILTIN_VALUES where name == key) {
        return values
    }
    None
}

private func holds(op: String, order: Ordering): Bool {
    match ((op, order)) {
        case ("==", Ordering.EQ) |
            ("!=", Ordering.LT) |
            ("!=", Ordering.GT) |
            ("<", Ordering.LT) |
            ("<=", Ordering.LT) |
            ("<=", Ordering.EQ) |
            (">", Ordering.GT) |
            (">=", Ordering.GT) |
            (">=", Ordering.EQ) => true
        case _ => false
    }
}

/**
 * `a` and `b` as cjc compares versions: their first three numbers, each at most 99, what follows left
 * out (`1.3.0-alpha` is `1.3.0`); `None` if either has none.
 */
func compareVersions(a: String, b: String): ?Ordering {
    let left = versionOf(a) ?? return None
    let right = versionOf(b) ?? return None
    for (i in 0..3 where left[i] != right[i]) {
        return left[i].compare(right[i])
    }
    Some(Ordering.EQ)
}

private func versionOf(text: String): ?Array<Int64> {
    var end = 0
    for (byte in text) {
        if ((byte < b'0' || byte > b'9') && byte != b'.') {
            break
        }
        end++
    }
    let parts = text[..end].split(".")
    if (parts.size < 3) {
        return None
    }
    let numbers = ArrayList<Int64>()
    for (part in parts[..3]) {
        let number = Int64.tryParse(part) ?? return None
        if (number > 99) {
            return None
        }
        numbers.add(number)
    }
    numbers.toArray()
}

/**
 * Whether `text` is a version cjc takes in a `@When`: three numbers of one or two digits.
 */
private func isVersionLiteral(text: String): Bool {
    let parts = text.split(".")
    parts.size == 3 &&
        parts
            .iterator()
            .all {
                part =>
                part.size >= 1 && part.size <= 2 &&
                    part.iterator().all { byte => byte >= b'0' && byte <= b'9' }
            }
}

/**
 * What a `@When` is wrong with, as cjc says it, where.
 */
@DerivePython
public struct WhenError <: Equatable<WhenError> {
    public WhenError(public let range: TextRange, public let message: String) {}

    public operator func ==(other: WhenError): Bool {
        range == other.range && message == other.message
    }

    public operator func !=(other: WhenError): Bool {
        !(this == other)
    }
}

/**
 * The `@When` among the annotations of `node`, `None` if it has none.
 */
public func whenOf(node: CjSyntaxNode): ?AnnotationNode {
    let annotated = AnyHasAnnotations.cast(node) ?? return None
    for (
        annotation in annotated.annotations() where (annotation.nameRef()?.text() ?? "") == "When"
    ) {
        return annotation
    }
    None
}

/**
 * The condition of `node`'s `@When`, `None` if it has none.
 */
public func conditionOf(node: CjSyntaxNode): ?CfgExpr {
    whenOf(node).map { annotation => WhenLowering().lower(annotation) }
}

/**
 * A `@When` as it is lowered, and what cjc rejects in it whatever the build.
 */
class WhenLowering {
    let errors = ArrayList<WhenError>()

    func lower(annotation: AnnotationNode): CfgExpr {
        let arg =
            annotation
                .annotationArgList()
                .flatMap { list => list.args().next() }
                .flatMap { arg => arg.expr() }
        match (arg) {
            case Some(expr) => condition(expr)
            case None =>
                invalid(
                    annotation.syntax,
                    "conditional compilation should have condition expression"
                )
        }
    }

    private func invalid(node: CjSyntaxNode, message: String): CfgExpr {
        errors.add(WhenError(node.textRange, message))
        CfgInvalid
    }

    private func condition(expr: AstExpr): CfgExpr {
        match (expr) {
            case AstExpr.AsParenExpr(it) =>
                match (it.expr()) {
                    case Some(inner) => condition(inner)
                    case None => invalid(it.syntax, INVALID_EXPR)
                }
            case AstExpr.AsRefExpr(it) =>
                match (flagOf(it)) {
                    case Some(name) => CfgFlag(name, false)
                    case None => invalid(it.syntax, INVALID_EXPR)
                }
            // only `debug` and `test` take a `!`, and only right before them
            case AstExpr.AsUnaryExpr(it) =>
                match ((it.op()?.text(), it.expr())) {
                    case (Some("!"), Some(AstExpr.AsRefExpr(ref))) =>
                        match (flagOf(ref)) {
                            case Some(name) => CfgFlag(name, true)
                            case None => invalid(it.syntax, INVALID_EXPR)
                        }
                    case _ => invalid(it.syntax, INVALID_EXPR)
                }
            case AstExpr.AsBinExpr(it) => binary(it)
            case _ => invalid(expr.syntax, INVALID_EXPR)
        }
    }

    private func flagOf(ref: RefExpr): ?String {
        match (ref.nameRef()?.text()) {
            case Some("debug") => Some("debug")
            case Some("test") => Some("test")
            case _ => None
        }
    }

    private func binary(it: BinExpr): CfgExpr {
        let op = it.op()?.text() ?? ""
        match (op) {
            // cjc evaluates both sides, and reports what is wrong in either
            case "&&" | "||" =>
                let left = it.lhs().map { one => condition(one) } ?? CfgInvalid
                let right = it.rhs().map { one => condition(one) } ?? CfgInvalid
                if (op == "&&") { CfgAnd(left, right) } else { CfgOr(left, right) }
            case "==" | "!=" | "<" | "<=" | ">" | ">=" => comparison(it, op)
            case _ => invalid(it.syntax, INVALID_EXPR)
        }
    }

    private func comparison(it: BinExpr, op: String): CfgExpr {
        let key =
            match (it.lhs()) {
                case Some(AstExpr.AsRefExpr(ref)) => ref.nameRef()?.text()
                case _ => None<String>
            }
        let name = key ?? return invalid(it.syntax, INVALID_EXPR)
        let value =
            match (it.rhs()) {
                case Some(AstExpr.AsStringLit(lit)) => contentOf(lit)
                case _ => None<String>
            }
        let text =
            value ??
                return invalid(
                    it.rhs().map { rhs => rhs.syntax } ?? it.syntax,
                    "conditional compilation's condition value should be string literal without interpolation"
                )
        // cjc's order: the condition, its value, then the operator
        if (let Some(values) <- builtinValues(name) && !values.contains(text)) {
            return invalid(
                it.syntax,
                "builtin condition '${name}' do not support '${text}', supported listed: '${String.join(values, delimiter: " ")}'"
            )
        }
        if (name == CJC_VERSION && !isVersionLiteral(text)) {
            return invalid(it.syntax, "cjc version's format should be 'xx.xx.xx'")
        }
        if (let Some(ops) <- builtinOps(name) && !ops.contains(op)) {
            return invalid(
                it.syntax,
                "conditional compilation '${name}' not support this op '${op}'"
            )
        }
        CfgCompare(name, op, text)
    }

    /**
     * The text of a string literal of no interpolation, `None` for one with.
     */
    private func contentOf(lit: StringLit): ?String {
        if (lit.interpolations().next().isSome()) {
            return None
        }
        let text = StringBuilder()
        for (token in lit.stringContentTokens()) {
            text.append(token.text())
        }
        text.toString()
    }
}

/**
 * What `@When` is evaluated against in `file`: its project's, its module's of the same key in place,
 * and its package's in place of those (a `cfg.toml`, `PackageModel.cfg`). Empty for a file of no
 * project.
 */
@CalcaTracked
public func cfgOfFile(db: AnalysisDatabase, file: SourceFile): Cfg {
    let project = db.project() ?? return Cfg([])
    let context = packageOfFile(db, file)
    for (module in project.modules(db)) {
        for (pkg in module.packages(db) where context == Some(pkg)) {
            let ofModule =
                match (module.cfg(db)) {
                    case Some(own) => own
                    case None => project.cfg(db)
                }
            return match (pkg.cfg(db)) {
                case Some(own) => ofModule.overriddenBy(own)
                case None => ofModule
            }
        }
    }
    project.cfg(db)
}

/**
 * The item tree of `file` as the build `cfgOfFile` makes sees it: what a false `@When` is on left
 * out, the members under it with it (#149). The item tree itself keeps every item and its condition,
 * so a change of the cfg runs this again, not the parse; one of a file of no `@When` is not read.
 */
@CalcaTracked
public func activeItemTree(db: AnalysisDatabase, file: SourceFile): ItemTree {
    let tree = itemTree(db, file)
    if (
        !tree.imports.iterator().any { one => one.condition.isSome() } && !hasConditions(tree.items)
    ) {
        return tree
    }
    let cfg = cfgOfFile(db, file)
    ItemTree(
        packageHeader: tree.packageHeader,
        imports: tree
            .imports
            .filter { one => one.condition.map { it => it.isActive(cfg) } ?? true },
        items: activeItems(tree.items, cfg)
    )
}

private func hasConditions(items: Array<Item>): Bool {
    items.iterator().any { item => item.condition.isSome() || hasConditions(item.members) }
}

private func activeItems(items: Array<Item>, cfg: Cfg): Array<Item> {
    items
        .filter { item => item.condition.map { it => it.isActive(cfg) } ?? true }
        .map {
            item =>
            if (hasConditions(item.members)) {
                Item(
                    item.id,
                    item.names,
                    item.modifiers,
                    item.macros,
                    activeItems(item.members, cfg),
                    condition: item.condition,
                    paramMacros: item.paramMacros,
                    isC: item.isC
                )
            } else {
                item
            }
        }
}

/**
 * Which nodes of a body or a signature are in the build: those with no `@When`, or one true under
 * the cfg of their file, read only once a `@When` is met, so that what has none does not depend on
 * it. `ALL_ACTIVE`, of no cfg, for code of no file of the project.
 */
public class ActiveFilter {
    private var known: ?Cfg = None

    /**
     * A filter of the cfg `read` gives, every node active if `None`.
     */
    public init(read: ?() -> Cfg) {
        this.read = read
    }

    private let read: ?() -> Cfg

    /**
     * Whether `node` is in the build.
     */
    public func isActive(node: CjSyntaxNode): Bool {
        if (read.isNone()) {
            return true
        }
        let condition = conditionOf(node) ?? return true
        condition.isActive(cfg())
    }

    /**
     * The cfg, read the first time; an empty one for a filter of none.
     */
    public func cfg(): Cfg {
        match ((known, read)) {
            case (Some(it), _) => it
            case (None, Some(reader)) =>
                let it = reader()
                known = it
                it
            case (None, None) => Cfg([])
        }
    }

    /**
     * The filter of `file`: `cfgOfFile`, read at the first `@When`.
     */
    public static func of(db: AnalysisDatabase, file: SourceFile): ActiveFilter {
        ActiveFilter(Some({ => cfgOfFile(db, file) }))
    }
}

/**
 * The filter of what is not in a file of the project: every node active, whatever its `@When`.
 */
public let ALL_ACTIVE = ActiveFilter(None)

/**
 * Code a false `@When` leaves out of the build, and why: `reasons`, as `CfgExpr.whyFalse`.
 */
@DerivePython
public struct InactiveCode <: Equatable<InactiveCode> {
    public InactiveCode(public let range: TextRange, public let reasons: Array<String>) {}

    public operator func ==(other: InactiveCode): Bool {
        range == other.range && reasons == other.reasons
    }

    public operator func !=(other: InactiveCode): Bool {
        !(this == other)
    }
}

/**
 * What the `@When`s of a file say: the code they leave out, outermost only (nothing inside it is
 * checked, as cjc checks nothing there), and what cjc rejects in them whatever the build, as it says
 * it. Code that a condition cjc rejects leaves out is not reported as left out: the error on the
 * condition says why. A condition neither cjc knows nor the cfg sets is not one: a `--cfg` the analysis does not see
 * may set it (#297), and its code is active.
 */
@DerivePython
public struct WhenDiagnostics <: Equatable<WhenDiagnostics> {
    public WhenDiagnostics(
        public let inactive: Array<InactiveCode>,
        public let errors: Array<WhenError>
    ) {}

    public operator func ==(other: WhenDiagnostics): Bool {
        inactive == other.inactive && errors == other.errors
    }

    public operator func !=(other: WhenDiagnostics): Bool {
        !(this == other)
    }
}

/**
 * The `WhenDiagnostics` of `file`; the cfg read only once a `@When` is met.
 */
@CalcaTracked
public func whenDiagnostics(db: AnalysisDatabase, file: SourceFile): WhenDiagnostics {
    let inactive = ArrayList<InactiveCode>()
    let errors = ArrayList<WhenError>()
    let filter = ActiveFilter.of(db, file)
    func visit(node: CjSyntaxNode): Unit {
        if (let Some(annotation) <- whenOf(node)) {
            let lowering = WhenLowering()
            let condition = lowering.lower(annotation)
            errors.add(all: lowering.errors)
            let known = filter.cfg()
            if (!condition.isActive(known)) {
                if (lowering.errors.isEmpty()) {
                    inactive.add(InactiveCode(node.textRange, condition.whyFalse(known)))
                }
                return
            }
        }
        for (child in node.children()) {
            visit(child)
        }
    }
    visit(parse(db, file).syntaxNode())
    WhenDiagnostics(inactive.toArray(), errors.toArray())
}
