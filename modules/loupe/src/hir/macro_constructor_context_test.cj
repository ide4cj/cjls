package loupe.hir

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.{AnalysisDatabase, SourceFile}

@Test
class MacroConstructorContextTest {
    @TestCase[mode in ["unserved", "served", "plain", "missing"]]
    func constructorEvidenceDoesNotRejectCompatibleIndexSetters(mode: String): Unit {
        // arrange
        let annotated = mode == "unserved" || mode == "served"
        let annotation = if (annotated) { "@A" } else { "" }
        let declaration =
            if (mode == "plain") {
                "struct Entry { public Entry(let value: Int64) {} }"
            } else {
                "struct Entry {}"
            }
        let (db, file, _) = workspaceMacroDatabase(
            """
            package m
            import m.ms.*
            ${annotation}
            ${declaration}
            func test(): Unit {
                let values = Array<?Entry>(1, repeat: None)
                values[0] = Entry(1)
            }
            """,
            std: ["std.core"]
        )
        if (mode == "served") {
            let request = requestNamed(db, file, "A")
            setMacroOutputs(
                db,
                [
                    (
                        request.call,
                        writtenOutput(request, "struct Entry { public Entry(let value: Int64) {} }")
                    )
                ]
            )
        }
        let expectedCtor =
            if (mode == "unserved" || mode == "missing") {
                CallResolutionOutcome.Unresolved
            } else {
                CallResolutionOutcome.Resolved
            }
        let expectedSetter =
            if (mode == "missing") {
                CallResolutionOutcome.Unresolved
            } else {
                CallResolutionOutcome.Resolved
            }
        let expectedIndex = if (mode == "missing") { "{unknown}" } else { "Option<Entry>" }

        // act
        let (constructor, setter, returned, indexed, hasDiagnostics) = constructorContextEvidence(
            db,
            file
        )

        // assert
        @Expect(constructor, expectedCtor)
        @Expect(setter, expectedSetter)
        @Expect(returned, "Entry")
        @Expect(indexed, expectedIndex)
        @Expect(hasDiagnostics, mode == "missing")
    }
}

/**
 * Observes the constructor and its enclosing setter separately: an opaque constructor can
 * have a known nominal return without claiming its unseen signature was resolved.
 */
private func constructorContextEvidence(
    db: AnalysisDatabase,
    file: SourceFile
): (CallResolutionOutcome, CallResolutionOutcome, String, String, Bool) {
    let item = itemTree(db, file).items.filter { one => one.names.contains("test") }[0]
    let def = DefId(db, ItemFile.Source(file), item.id)
    let hir = body(db, def)
    let inferred = inferBody(db, def)
    let indices = ArrayList<ExprId>()
    let constructors = ArrayList<(ExprId, ExprId)>()
    for (i in 0..hir.exprs.size) {
        match (hir.exprs[i]) {
            case IndexExpr(_, _) => indices.add(ExprId(i))
            case CallExpr(callee, _) =>
                match (hir[callee]) {
                    case PathExpr("Entry", _) => constructors.add((callee, ExprId(i)))
                    case _ => ()
                }
            case _ => ()
        }
    }
    let (callee, call) = constructors[0]
    (
        inferred.callOf(callee).getOrThrow().outcome,
        inferred.callOf(indices[0]).getOrThrow().outcome,
        inferred[call].getOrThrow().text(db),
        inferred[indices[0]].getOrThrow().text(db),
        !inferred.diagnostics.isEmpty()
    )
}
