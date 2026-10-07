package project_model

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.hir.*

/**
 * Each declaration of the workspace whose signature, as types, holds an error, by `onFailed`; how
 * many types its signatures hold, each counted with the types inside it.
 */
func lowerEverySignature(ws: BenchWorkspace, onFailed!: (SourceFile, DefId, SignatureTypes) -> Unit = {_, _, _ => ()}): Int64 {
    var count = 0
    for ((_, file, _) in ws.files) {
        for (def in defsOf(ws, file)) {
            let types = signatureTypes(ws.db, def)
            let all = types.params.concat(types.ty.map {ty => [ty]} ?? []).concat(types.supers)
            var failed = !types.errors.isEmpty()
            for (ty in all) {
                let (size, errors) = sizeOf(ws.db, ty)
                count += size
                failed = failed || errors > 0
            }
            if (failed) {
                onFailed(file, def, types)
            }
        }
    }
    count
}

/**
 * How many types `ty` is made of, itself among them, and how many of them are errors.
 */
func sizeOf(db: AnalysisDatabase, ty: Ty): (Int64, Int64) {
    let inner = match (ty.kind(db)) {
        case DeclTy(_, args) => args
        case TupleTy(elements) => elements
        case FuncTy(params, ret, _) => params.concat([ret])
        case VArrayTy(element, _) => [element]
        case ErrorTy => return (1, 1)
        case _ => Array<Ty>()
    }
    var size = 1
    var errors = 0
    for (one in inner) {
        let (s, e) = sizeOf(db, one)
        size += s
        errors += e
    }
    (size, errors)
}

/**
 * The signatures of this repository's declarations as types: `cjpm bench '--filter=SignatureTypesBench.*'`.
 */
@Test
class SignatureTypesBench {
    @Bench
    func lowerEverySignatureOfTheWorkspace(): Int64 {
        lowerEverySignature(workspace())
    }
}
