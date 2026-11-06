package loupe.hir

import std.collection.*
import loupe.db.{AnalysisDatabase, SourceFile}

/**
 * Constraints from one synthesized lambda's body. They are journaled with inference writes so an
 * overload trial cannot tell the lambda anything after that candidate has been discarded.
 */
class LambdaConstraints {
    let bounds = ArrayList<(Ty, Ty, Bool)>()
    var rejected = 0

    LambdaConstraints(let base: Int64, let count: Int64) {}

    func contains(db: AnalysisDatabase, ty: Ty): Bool {
        match (ty.kind(db)) {
            case InferTy(index) => index >= base && index < base + count
            case _ => false
        }
    }

    func solve(db: AnalysisDatabase, from: ?SourceFile, option: ?DefId): Array<?Ty> {
        if (rejected > 0) {
            return Array<?Ty>(count, repeat: None)
        }
        let representatives = Array(count) { i => i }
        // Built-in binary operators require the same operand type. Merge these variables before
        // solving bounds, including a chain such as `x + y + 1` whose first operands tell no type.
        for ((left, right, equal) in bounds) {
            if (!equal || !contains(db, left) || !contains(db, right)) {
                continue
            }
            let a =
                match (left.kind(db)) {
                    case InferTy(i) => representatives[i - base];
                    case _ => 0
                }
            let b =
                match (right.kind(db)) {
                    case InferTy(i) => representatives[i - base];
                    case _ => 0
                }
            for (i in 0..count where representatives[i] == b) {
                representatives[i] = a
            }
        }
        let aliases = Array<?Ty>(count) { i => Ty(db, InferTy(base + representatives[i])) }
        var solved = Array<?Ty>(count, repeat: None)
        // A member owner's argument and another lambda parameter can constrain each other:
        // `x.put(y) + 1` first solves Box<T>'s T, then y <: T. Keep symbolic endpoints while
        // propagating solved endpoints, so each round can still check all original bounds.
        for (_ in 0..count + 1) {
            let previous = solved
            let known = Array<?Ty>(count) { i => previous[i] ?? aliases[i] }
            let solver = TypeArgSolver(db, base, count, from, option)
            for ((left, right, equal) in bounds) {
                let a = replaceVars(db, left, base, aliases)
                let b = replaceVars(db, right, base, aliases)
                if (a == b) {
                    continue
                }
                let resolvedA = replaceVars(db, a, base, known)
                let resolvedB = replaceVars(db, b, base, known)
                solver.constrain(a, b)
                solver.constrain(resolvedA, b)
                solver.constrain(a, resolvedB)
                if (equal) {
                    solver.constrain(b, a)
                    solver.constrain(resolvedB, a)
                    solver.constrain(b, resolvedA)
                }
            }
            let next = solver.solve()
            if (next == solved) {
                break
            }
            solved = next
        }
        let solution = solved
        Array(count) { i => solution[representatives[i]] }
    }
}

/**
 * A bounded search keeps no candidate's inference writes. Two distinct complete solutions are
 * enough to prove ambiguity; exhausting the budget proves only that analysis is unavailable.
 */
class LambdaSearch {
    let solutions = ArrayList<Array<Ty>>()
    var trials = 0
    var limited = false
    var unavailable: ?Ty = None
}

/**
 * Concrete body replay must also reject errors in statements whose values are dropped.
 */
class LambdaReplay {
    var errors = 0
}
