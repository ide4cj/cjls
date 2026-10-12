package project_model

import std.collection.*
import std.env.getVariable
import std.sort.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.hir.*
import loupe.syntax.parse

/**
 * Each expression of a body of the workspace of no type known, by `onUnknown`; how many expressions
 * there are.
 */
func inferEveryBody(ws: BenchWorkspace, onUnknown!: (SourceFile, DefId, ExprId) -> Unit = {_, _, _ => ()}): Int64 {
    var count = 0
    for ((_, file, _) in ws.files) {
        for (def in defsOf(ws, file)) {
            let result = inferBody(ws.db, def)
            for (i in 0..result.exprs.size) {
                if (let Some(ty) <- result.exprs[i] && isUnknown(ws.db, ty)) {
                    onUnknown(file, def, ExprId(i))
                }
            }
            count += result.exprs.size
        }
    }
    count
}

/**
 * The types of this repository's bodies, read once they are computed: what a run after the first
 * measures is the memos read, not the inference. `cjHeapSize=2GB cjpm bench '--filter=InferenceBench.*'`.
 */
@Test
class InferenceBench {
    @Bench
    func readTheTypesOfEveryBodyOfTheWorkspaceComputed(): Int64 {
        inferEveryBody(workspace())
    }
}

/**
 * The expressions `id` holds, in the body `hir`.
 */
func childrenOf(hir: Body, id: ExprId): Array<ExprId> {
    let opt = {one: ?ExprId => match (one) {
        case Some(e) => [e]
        case None => Array<ExprId>()
    }}
    let ofArgs = {args: Array<CallArg> => args.map {arg => arg.expr}}
    let ofArms = {
        arms: Array<MatchArm> =>
        let found = ArrayList<ExprId>()
        for (arm in arms) {
            found.add(all: opt(arm.guard))
            found.add(all: opt(arm.condition))
            found.add(arm.body)
        }
        found.toArray()
    }
    match (hir[id]) {
        case StrExpr(parts) => parts
        case FieldExpr(receiver, _, _) => [receiver]
        case CallExpr(callee, args) => [callee].concat(ofArgs(args))
        case IndexExpr(base, indices) => [base].concat(indices)
        case UnaryExpr(_, operand) => [operand]
        case BinaryExpr(_, lhs, rhs) => [lhs, rhs]
        case IsExpr(inner, _) => [inner]
        case AsExpr(inner, _) => [inner]
        case RangeExpr(start, end, step, _) => opt(start).concat(opt(end)).concat(opt(step))
        case PostfixExpr(inner, _) => [inner]
        case TupleExpr(elements) => elements
        case ArrayExpr(elements) => elements
        case IfExpr(condition, then, otherwise) => [condition, then].concat(opt(otherwise))
        case LetExpr(_, value) => [value]
        case MatchExpr(scrutinee, arms) => opt(scrutinee).concat(ofArms(arms))
        case QuestMatchExpr(selector, arms) => [selector].concat(ofArms(arms))
        case TryExpr(resources, tried, catches, cleanup) =>
            resources.map {one => one.value}.concat([tried]).concat(catches.map {one => one.body}).concat(opt(cleanup))
        case ForExpr(_, iterated, guard, loopBody) => [iterated].concat(opt(guard)).concat([loopBody])
        case WhileExpr(condition, loopBody) => [condition, loopBody]
        case DoWhileExpr(loopBody, condition) => [loopBody, condition]
        case SynchronizedExpr(lock, block) => [lock, block]
        case ThrowExpr(inner) => [inner]
        case UnsafeExpr(inner) => [inner]
        case ConvExpr(_, inner) => [inner]
        case ReturnExpr(value) => opt(value)
        case SpawnExpr(context, lambda) => opt(context).concat([lambda])
        case LambdaExpr(_, block) => [block]
        case VArrayExpr(_, args) => ofArgs(args)
        case BlockExpr(stmts) =>
            let found = ArrayList<ExprId>()
            for (stmt in stmts) {
                match (stmt) {
                    case LetStmt(_, _, value) => found.add(all: opt(value))
                    case ExprStmt(expr) => found.add(expr)
                    case FuncStmt(_) => ()
                }
            }
            found.toArray()
        case MacroExpr(call) => ofArgs(call.args)
        case _ => []
    }
}

/**
 * What `id`, an expression of no type known of the body of `def` none of whose children is one, is,
 * as #48's step 8c′ counted them before the error type was split (D77).
 */
func rootKindOf(db: AnalysisDatabase, def: DefId, hir: Body, result: InferenceResult, id: ExprId): String {
    match (hir[id]) {
        case MacroExpr(_) => "macro call"
        case QuoteExpr => "quote"
        case PathExpr(name, _) => match (resolveBodyName(db, def, exprScopes(db, def).scopeOf(id), name)) {
            case Values(targets) where targets.size == 1 => match (targets[0]) {
                case LocalOf(_) => "local"
                case _ => "name found"
            }
            case InFile(Found(_)) => "name found"
            case _ => "name not found"
        }
        case FieldExpr(_, _, _) => match (resolveField(db, def, id)) {
            case OfValue where result.fieldOf(id).isNone() => "member not found"
            case OfValue => "member found"
            case _ => "member of a type or package"
        }
        case CallExpr(_, _) => "call not solved"
        case LambdaExpr(_, _) => "lambda"
        case LitExpr(_) => "literal"
        case ArrayExpr(_) => "array"
        case BinaryExpr(op, _, _) => "operator ${op}"
        case UnaryExpr(op, _) => "operator ${op}"
        case IndexExpr(_, _) => "index"
        case _ => "other"
    }
}

/**
 * Where `id` of the body of `def` is written, and the start of its text.
 */
func textOf(ws: BenchWorkspace, file: SourceFile, def: DefId, id: ExprId): String {
    let db = ws.db
    let root = parse(db, file).syntaxNode()
    let ptr = bodyWithSourceMap(db, def).sourceMap.exprs.get(id.index) ?? return "?"
    let node = (ptr ?? return "no node").tryToNode(root) ?? return "?"
    let text = node.text().replace("\n", " ")
    let short = if (text.size > 100) {
        text[..100]
    } else {
        text
    }
    "${ws.paths.path(file.fileId(db))}@${node.textRange.start}: ${short}"
}

/**
 * Each expression of the workspace's bodies: whether it is of no type known, why, and what it was
 * before the error type was split (D77). A cold pass over every body, 2 GB of heap: run with
 * `CJLS_CENSUS=1 cjHeapSize=2GB cjpm test --show-all-output --target-dir target/test
 * '--filter=InferenceCensusTest.*'`, else it passes doing nothing.
 */
@Test
class InferenceCensusTest {
    @TestCase
    func eachExpressionOfTheWorkspaceIsReachedAndOnlyATypeOrPackageBeforeADotIsNoValue() {
        if (getVariable("CJLS_CENSUS").isNone()) {
            return
        }
        let ws = workspace()
        let db = ws.db
        let counts = HashMap<String, Int64>()
        let add = {key: String => counts[key] = (counts.get(key) ?? 0) + 1}
        var total = 0
        var unknown = 0
        var noValue = 0
        let wrongNoValue = ArrayList<String>()
        for ((_, file, _) in ws.files) {
            for (def in defsOf(ws, file)) {
                let hir = body(db, def)
                let result = inferBody(db, def)
                total += hir.exprs.size
                // the receivers before a `.` that names a type's or a package's members, and those before them
                let qualifiers = HashSet<Int64>()
                for (i in 0..hir.exprs.size) {
                    if (let FieldExpr(receiver, _, _) <- hir[ExprId(i)]) {
                        match (resolveField(db, def, ExprId(i))) {
                            case PackageMembers(_) | TypeMembers(_) => qualifiers.add(receiver.index)
                            case NoField => match (receiverOf(db, def, receiver)) {
                                case PackageReceiver(_) | TypesReceiver(_) => qualifiers.add(receiver.index)
                                case _ => ()
                            }
                            case _ => ()
                        }
                    }
                }
                let isUnknownAt = {id: ExprId => match (result[id]) {
                    case Some(ty) => isUnknown(db, ty)
                    case None => false
                }}
                for (i in 0..hir.exprs.size) {
                    let id = ExprId(i)
                    let ty = match (result[id]) {
                        case Some(one) => one
                        case None =>
                            noValue++
                            if (!qualifiers.contains(i)) {
                                wrongNoValue.add("${def}: ${i}")
                            }
                            continue
                    }
                    if (!isUnknown(db, ty)) {
                        continue
                    }
                    unknown++
                    let kind = match (ty.kind(db)) {
                        case TodoTy(why) => "todo(${why})"
                        case _ => "error"
                    }
                    let isCascade = childrenOf(hir, id).iterator().any {one => isUnknownAt(one)}
                    let key = if (isCascade) {
                        "${kind} cascade"
                    } else {
                        "${kind} root ${rootKindOf(db, def, hir, result, id)}"
                    }
                    add(key)
                    // `CJLS_CENSUS_SAMPLES=<prefix>` prints the first of those of each key it begins
                    if (let Some(prefix) <- getVariable("CJLS_CENSUS_SAMPLES") && key.startsWith(prefix) &&
                        counts[key] <= 12) {
                        println("sample [${key}] ${textOf(ws, file, def, id)}")
                    }
                    add("${kind}")
                }
            }
        }
        println("census: ${total} expressions, ${unknown} of no type known, ${noValue} no value")
        let keys = counts.keys().toArray()
        sort(keys, by: {a: String, b: String => a.compare(b)})
        for (key in keys) {
            println("census: ${key}: ${counts[key]}")
        }
        @Expect(counts.get("todo(not inferred)"), None)
        @Expect(wrongNoValue.toArray(), Array<String>())
    }
}
