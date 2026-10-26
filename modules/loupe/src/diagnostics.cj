package loupe

import std.collection.*
import std.deriving.*
import std.sort.*
import cjsyntax.{CjSyntaxNode, message}
import cjsyntax.ast.ArgList as AstArgList
import cjsyntax.ast.SourceFile as AstSourceFile
import cjsyntax.ast.{AnyHasName, Arg, BinExpr, ImportDecl, ImportTree, InitDecl, TrailingLambdaExpr}
import ginkgo.{SyntaxElement, TextRange}
import loupe.db.{AnalysisDatabase, MacroSeverity, SourceFile}
import loupe.hir.*
import loupe.syntax.parse
import loupe.vfs.FileId

@Derive[Equatable]
public enum Severity {
    | Error
    | Warning
    // not a fault: what a reader may want to know, as code a `@When` leaves out
    | Hint
}

/**
 * Something wrong in a file, or worth knowing of it. `range` is where its source put it, empty ones
 * included, as "expected `}`" at the end of a file (A12). `unnecessary` for code a build leaves
 * out, which an editor shows faded.
 */
@Derive[Equatable]
public struct Diagnostic {
    public Diagnostic(public let range: TextRange, public let severity: Severity, public let message: String,
        public let unnecessary!: Bool = false) {}
}

/**
 * What is wrong in a file, in the order of the text: what the lexer and the parser found, what its
 * `@When`s say (the code they leave out, what cjc rejects in them), what is wrong with its scope, what
 * the workspace's macros reported running its calls, and what inference found in its bodies, those of an item the
 * macro server's output replaces in that output (D132); for a file
 * the build leaves out (#318), what the parser found and that it is inactive. Empty for a file the
 * database does not know.
 *
 * Not a query: every source of diagnostics is one (`parse`, `whenDiagnostics`, `scopeDiagnostics`,
 * `packageHeaderError`, `macroDiagnostics`, `inferBody`), remembered there, and this only collects
 * their results (A11).
 */
public func diagnostics(db: AnalysisDatabase, fileId: FileId): Array<Diagnostic> {
    let file = db.sourceFile(fileId) ?? return []
    let result = ArrayList<Diagnostic>()
    result.add(all: parse(db, file).errors.map {error => Diagnostic(error.range, Severity.Error, message(error.error))})
    // a file the build leaves out is all inactive, and nothing in it is checked
    if (let Some(reason) <- inactiveReasonOf(db, file)) {
        result.add(Diagnostic(codeRange(parse(db, file).syntaxNode()), Severity.Hint, "code is inactive: ${reason}",
            unnecessary: true))
        return result.toArray()
    }
    let conditional = whenDiagnostics(db, file)
    result.add(all: conditional.errors.map {error => Diagnostic(error.range, Severity.Error, error.message)})
    result.add(all: conditional.inactive.map {
        code => Diagnostic(code.range, Severity.Hint,
            "code is inactive due to @When: ${String.join(code.reasons, delimiter: " and ")}", unnecessary: true)
    })
    let root = parse(db, file).syntaxNode()
    if (let Some(message) <- packageHeaderError(db, file)) {
        if (let Some(header) <- (AstSourceFile.cast(root)?.packageHeader() ?? None)) {
            let range = header.macroToken()?.textRange ?? header.packageToken()?.textRange ??
                header.syntax.textRange
            result.add(Diagnostic(range, Severity.Error, message))
        }
    }
    result.add(all: scopeDiagnosticsOf(db, file, root))
    result.add(all: macroDiagnostics(db, file).map {
        one =>
        let severity = match (one.severity) {
            case MacroError => Severity.Error
            case MacroWarning => Severity.Warning
        }
        Diagnostic(one.range, severity, one.message)
    })
    let read = readServerCallsOf(db, file)
    for (def in bodiesOf(db, ItemFile.Source(file), leavingOut: read.map {call => call.item(db)})) {
        result.add(all: inferenceDiagnostics(db, def, root))
    }
    result.add(all: expansionDiagnostics(db, file, read))
    let sorted = result.toArray()
    sort(sorted, stable: true, by: {a: Diagnostic, b: Diagnostic => a.range.start.compare(b.range.start)})
    sorted
}

/**
 * The declarations of `file` that have a body, their members among them; none under the items `leavingOut`.
 */
func bodiesOf(db: AnalysisDatabase, file: ItemFile, leavingOut!: Array<ItemId> = []): Array<DefId> {
    let found = ArrayList<DefId>()
    let left = HashSet<ItemId>(leavingOut)
    func add(items: Array<Item>): Unit {
        for (item in items where !left.contains(item.id)) {
            match (item.kind) {
                case Func | Main | Macro | Var | Prop | Init | PrimaryInit | Finalizer =>
                    found.add(DefId(db, file, item.id))
                case _ => ()
            }
            add(item.members)
        }
    }
    add(itemTreeOf(db, file).items)
    found.toArray()
}

/**
 * What inference found wrong in the bodies of the outputs of the macro server `read`, the calls of `file` whose items
 * are read through them (D132): in text an output copied, where it was copied from; in text the macro wrote, at the
 * head of the call, as `macroDiagnostics` puts the macro's own. None of an output older than the text, whose spans may
 * no longer say where the text is: its item has none until the server answers again.
 */
func expansionDiagnostics(db: AnalysisDatabase, file: SourceFile, read: Array<MacroCallId>): Array<Diagnostic> {
    if (read.isEmpty()) {
        return []
    }
    let current = HashSet<MacroCallId>()
    for (request in macroRequests(db, file) where request.current) {
        current.add(request.call)
    }
    let found = ArrayList<Diagnostic>()
    for (call in read where current.contains(call)) {
        let (_, head) = macroCallHeadOf(db, call) ?? continue
        let root = expansionParse(db, call).syntaxNode()
        for (def in bodiesOf(db, ItemFile.Expansion(call))) {
            for (one in inferenceDiagnostics(db, def, root)) {
                found.add(Diagnostic(sourceRangeOf(db, call, one.range) ?? head, one.severity, one.message))
            }
        }
    }
    found.toArray()
}

/**
 * What inference found wrong in the body of `def`, where it is written: none about an expression a
 * desugaring made (R3's `ShouldDiagnose`), which the user did not write (A29).
 */
func inferenceDiagnostics(db: AnalysisDatabase, def: DefId, root: CjSyntaxNode): Array<Diagnostic> {
    let inferred = inferBody(db, def)
    if (inferred.diagnostics.isEmpty()) {
        return []
    }
    let lowered = bodyWithSourceMap(db, def)
    let nodeOf = {
        id: ExprId =>
        let origin = lowered.sourceMap.exprs.get(id.index) ?? return None<CjSyntaxNode>
        let source = match (origin) {
            case WrittenSource(source) => source
            case _ => return None<CjSyntaxNode>
        }
        if (lowered.sourceMap.exprAtSource(source) != Some(id)) {
            return None<CjSyntaxNode>
        }
        if (source.expansion.isSome()) { source.node(db, def.file(db)) } else { source.ptr.tryToNode(root) }
    }
    let found = ArrayList<Diagnostic>()
    let report = {id: ExprId, range: TextRange, message: String =>
        let source = match (lowered.sourceMap.exprs.get(id.index)) {
            case Some(WrittenSource(source)) => source
            case _ => return
        }
        let mapped = if (let Some(call) <- source.expansion) {
            sourceRangeOf(db, call, range) ?? (macroCallHeadOf(db, call) ?? return)[1]
        } else { range }
        found.add(Diagnostic(mapped, Severity.Error, message))
    }
    for (diagnostic in inferred.diagnostics) {
        match (diagnostic) {
            case TypeMismatch(id, expected, actual) =>
                let node = nodeOf(id) ?? continue
                let message = match ((lowered.body[id], actual.kind(db))) {
                    case (LitExpr(_), PrimTy(name)) where name.startsWith("Int") || name.startsWith("UInt") =>
                        "cannot convert an integer literal to type '${expected.text(db)}'"
                    case _ => "mismatched types: expected '${expected.text(db)}', found '${actual.text(db)}'"
                }
                report(id, node.textRange, message)
            case VArraySizeMismatch(id, expected, actual) =>
                let node = nodeOf(id) ?? continue
                report(id, node.textRange,
                    "mismatch 'VArray' type's size: expected size is ${expected}, found ${actual}")
            case ArgCount(call, params, given) =>
                let node = nodeOf(call) ?? continue
                let taken = params.size
                let list = String.join(params.map {one => one.text(db)}, delimiter: ", ")
                let what = match ((given < taken, given - taken == 1 || taken - given == 1)) {
                    case (true, true) => "missing argument"
                    case (true, false) => "missing arguments"
                    case (false, true) => "extra argument given"
                    case (false, false) => "extra arguments given"
                }
                let plural = if (taken == 1) {
                    ""
                } else {
                    "s"
                }
                report(call, TextRange(argsStart(node), node.textRange.end),
                    "${what} for parameter list '(${list})' in call: expected ${taken} argument${plural}, found ${given}")
            case ArgName(call, at, why) =>
                let node = nodeOf(call) ?? continue
                let range = argRange(node, at) ?? continue
                let message = match (why) {
                    case UnknownName(name) => "unknown named argument prefix '${name}:'"
                    case NameTwice(name) => "named argument prefix '${name}:' cannot appeared more than once in call"
                    case NeedsName(names) =>
                        let prefixes = String.join(names.map {name => "'${name}:'"}, delimiter: " or ")
                        "missing argument prefix ${prefixes} for named parameter"
                    case NameOfValue => "named argument cannot be used in variable function call"
                }
                report(call, range, message)
            case InvalidBinaryOperator(id, left, right) =>
                let node = nodeOf(id) ?? continue
                // at the operator, as cjc's
                let op = (BinExpr.cast(node)?.op() ?? None) ?? continue
                report(id, op.textRange,
                    "invalid binary operator '${op.text()}' on type '${left.text(db)}' and '${right.text(db)}'")
        }
    }
    found.toArray()
}

/**
 * Where the argument at `at` of the call `node` is: one in its parentheses, else its trailing lambda.
 */
func argRange(node: CjSyntaxNode, at: Int64): ?TextRange {
    let trailing = TrailingLambdaExpr.cast(node)
    let args: Array<Arg> = match (callArgList(node)) {
        case Some(list) => list.args() |> collectArray
        case _ => []
    }
    match (args.get(at)) {
        case Some(arg) => arg.syntax.textRange
        case None => (trailing?.lambda()?.syntax.textRange)
    }
}

/**
 * Where the arguments of the call `node` start, as cjc puts a wrong count of them: its `(`, else its
 * trailing lambda.
 */
func argsStart(node: CjSyntaxNode): Int64 {
    (callArgList(node)?.syntax.textRange.start) ??
        (TrailingLambdaExpr.cast(node)?.lambda()?.syntax.textRange.start) ?? node.textRange.start
}

/**
 * The written argument list of an ordinary or built-in call, before a trailing lambda if present.
 */
func callArgList(node: CjSyntaxNode): ?AstArgList {
    let callee = TrailingLambdaExpr.cast(node).flatMap {one => one.callee()}.map {one => one.syntax} ?? node
    callee.children() |> filterMap {child: CjSyntaxNode => AstArgList.cast(child)} |> first
}

/**
 * What is wrong with the scope of `file`, where cjc puts it: a path that fails from its start to
 * its last name, a name brought twice or shadowed at that name, a declaration at its name; and the
 * `common` declarations no `specific` one completes, at their names (#318).
 */
func scopeDiagnosticsOf(db: AnalysisDatabase, file: SourceFile, root: CjSyntaxNode): Array<Diagnostic> {
    let pkg = packageOfFile(db, file) ?? return []
    let ids = itemIdMap(db, file)
    let found = ArrayList<Diagnostic>()
    for (one in noSpecifics(db, pkg, file)) {
        let node = ids.node(one.def.item(db), root) ?? continue
        found.add(Diagnostic(declNameRange(node), Severity.Error, one.message))
    }
    for (one in scopeDiagnostics(db, pkg, file)) {
        let range = match (one.at) {
            case AtImport(site) =>
                let decl = ids.node(site.item, root).flatMap {node => ImportDecl.cast(node)} ?? continue
                let tree = decl.importTree() ?? continue
                let leaf = importLeaf(tree, site.path) ?? continue
                if (one.problem.isWarning()) {
                    nameOfLeaf(leaf)
                } else {
                    TextRange(tree.syntax.textRange.start, nameOfLeaf(leaf).end)
                }
            case AtDecl(def, _) =>
                let node = ids.node(def.item(db), root) ?? continue
                let name = AnyHasName.cast(node).flatMap {it => it.name()}
                name?.syntax.textRange ?? continue
        }
        let severity = if (one.problem.isWarning()) {
            Severity.Warning
        } else {
            Severity.Error
        }
        found.add(Diagnostic(range, severity, one.problem.message()))
    }
    found.toArray()
}

/**
 * The range of `root` from its first token that is no trivia to its last, empty at its start if it
 * has none.
 */
func codeRange(root: CjSyntaxNode): TextRange {
    var start: ?Int64 = None
    var end = root.textRange.start
    for (element in root.descendantsWithTokens()) {
        if (let SyntaxElement.Token(token) <- element && !token.kind.isTrivia()) {
            if (start.isNone()) {
                start = token.textRange.start
            }
            end = token.textRange.end
        }
    }
    TextRange(start ?? end, end)
}

/**
 * The name of the declaration `node`, its `init` for a constructor, the whole of it for one of
 * neither.
 */
func declNameRange(node: CjSyntaxNode): TextRange {
    if (let Some(name) <- AnyHasName.cast(node).flatMap {it => it.name()}) {
        return name.syntax.textRange
    }
    InitDecl.cast(node).flatMap {decl => decl.initToken()}.map {token => token.textRange} ?? node.textRange
}

/**
 * The `index`th of the paths `tree` imports, one per leaf of its braces, as the item tree counts them.
 */
func importLeaf(tree: ImportTree, index: Int64): ?ImportTree {
    let leaves = ArrayList<ImportTree>()
    func add(one: ImportTree): Unit {
        match (one.importTreeList()) {
            case Some(list) => for (inner in list.importTrees()) {
                add(inner)
            }
            case None => leaves.add(one)
        }
    }
    add(tree)
    leaves.get(index)
}

/**
 * The name a leaf of an import brings: its alias, else its last name, else its `*`.
 */
func nameOfLeaf(leaf: ImportTree): TextRange {
    if (let Some(name) <- leaf.importAlias().flatMap {alias => alias.name()}) {
        return name.syntax.textRange
    }
    var last: ?TextRange = None
    for (name in leaf.nameRefs()) {
        last = name.syntax.textRange
    }
    last ?? leaf.starToken()?.textRange ?? leaf.syntax.textRange
}
