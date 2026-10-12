package loupe

import std.collection.*
import std.deriving.*
import std.sort.*
import ginkgo.TextRange
import cjsyntax.{CjSyntaxNode, message}
import cjsyntax.ast.{AnyHasName, CallExpr, ImportDecl, ImportTree, TrailingLambdaExpr}
import loupe.vfs.FileId
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.hir.*
import loupe.syntax.parse

@Derive[Equatable]
public enum Severity {
    | Error
    | Warning
}

/**
 * Something wrong in a file. `range` is where its source put it, empty ones included, as "expected
 * `}`" at the end of a file (A12).
 */
@Derive[Equatable]
public struct Diagnostic {
    public Diagnostic(public let range: TextRange, public let severity: Severity, public let message: String) {}
}

/**
 * What is wrong in a file, in the order of the text: what the lexer and the parser found, what is
 * wrong with its scope, and what inference found in its bodies. Empty for a file the database does not know.
 *
 * Not a query: every source of diagnostics is one (`parse`, `scopeDiagnostics`, `inferBody`), remembered there, and this
 * only collects their results (A11).
 */
public func diagnostics(db: AnalysisDatabase, fileId: FileId): Array<Diagnostic> {
    let file = db.sourceFile(fileId) ?? return []
    let result = ArrayList<Diagnostic>()
    result.add(all: parse(db, file).errors.map {error => Diagnostic(error.range, Severity.Error, message(error.error))})
    let root = parse(db, file).syntaxNode()
    result.add(all: scopeDiagnosticsOf(db, file, root))
    for (def in bodiesOf(db, file)) {
        result.add(all: inferenceDiagnostics(db, def, root))
    }
    let sorted = result.toArray()
    sort(sorted, stable: true, by: {a: Diagnostic, b: Diagnostic => a.range.start.compare(b.range.start)})
    sorted
}

/**
 * The declarations of `file` that have a body, their members among them.
 */
func bodiesOf(db: AnalysisDatabase, file: SourceFile): Array<DefId> {
    let found = ArrayList<DefId>()
    func add(items: Array<Item>): Unit {
        for (item in items) {
            match (item.kind) {
                case Func | Main | Macro | Var | Prop | Init | PrimaryInit | Finalizer =>
                    found.add(DefId(db, ItemFile.Source(file), item.id))
                case _ => ()
            }
            add(item.members)
        }
    }
    add(itemTree(db, file).items)
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
        let ptr = lowered.sourceMap.exprs.get(id.index) ?? return None<CjSyntaxNode>
        let one = ptr ?? return None<CjSyntaxNode>
        if (lowered.sourceMap.exprAt(one) != Some(id)) {
            return None<CjSyntaxNode>
        }
        one.tryToNode(root)
    }
    let found = ArrayList<Diagnostic>()
    for (diagnostic in inferred.diagnostics) {
        match (diagnostic) {
            case TypeMismatch(id, expected, actual) =>
                let node = nodeOf(id) ?? continue
                let message = match ((lowered.body[id], actual.kind(db))) {
                    case (LitExpr(_), PrimTy(name)) where name.startsWith("Int") || name.startsWith("UInt") =>
                        "cannot convert an integer literal to type '${expected.text(db)}'"
                    case _ => "mismatched types: expected '${expected.text(db)}', found '${actual.text(db)}'"
                }
                found.add(Diagnostic(node.textRange, Severity.Error, message))
            case ArgCount(call, params, given) =>
                let node = nodeOf(call) ?? continue
                let taken = params.size
                let list = String.join(params.map {one => one.text(db)}, delimiter: ", ")
                let what = if (given < taken) {
                    "missing argument"
                } else {
                    "extra argument given"
                }
                let plural = if (taken == 1) {
                    ""
                } else {
                    "s"
                }
                found.add(Diagnostic(TextRange(argsStart(node), node.textRange.end), Severity.Error,
                    "${what} for parameter list '(${list})' in call: expected ${taken} argument${plural}, found ${given}"))
        }
    }
    found.toArray()
}

/**
 * Where the arguments of the call `node` start, as cjc puts a wrong count of them: its `(`, else its
 * trailing lambda.
 */
func argsStart(node: CjSyntaxNode): Int64 {
    let call = match (TrailingLambdaExpr.cast(node)) {
        case Some(trailing) => match (trailing.callee().flatMap {callee => CallExpr.cast(callee.syntax)}) {
            case Some(inner) => inner
            case None => return (trailing.lambda()?.syntax.textRange.start) ?? node.textRange.start
        }
        case None => CallExpr.cast(node) ?? return node.textRange.start
    }
    (call.argList()?.syntax.textRange.start) ?? node.textRange.start
}

/**
 * What is wrong with the scope of `file`, where cjc puts it: a path that fails from its start to
 * its last name, a name brought twice or shadowed at that name, a declaration at its name.
 */
func scopeDiagnosticsOf(db: AnalysisDatabase, file: SourceFile, root: CjSyntaxNode): Array<Diagnostic> {
    let pkg = packageOfFile(db, file) ?? return []
    let ids = itemIdMap(db, file)
    let found = ArrayList<Diagnostic>()
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
