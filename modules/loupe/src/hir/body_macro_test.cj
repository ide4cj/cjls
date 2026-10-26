package loupe.hir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.{Kind, SyntaxNodePtr, TextRange}
import rope.Rope
import cjsyntax.ast.Decl
import loupe.syntax.parse
import loupe.db.*
import loupe.fixture.*

/**
 * A call of `serverCalls` as a line: its macro, its ordinal, `/` if it is in its item (D117), `!` if it is read.
 */
func describeCall(db: AnalysisDatabase, one: ServerCall): String {
    let inItem = if (one.call.inBody(db).isSome()) {
        "/"
    } else {
        ""
    }
    let read = if (one.read) {
        "!"
    } else {
        ""
    }
    "${one.definition.name}${one.call.index(db)}${inItem}${read}"
}

/**
 * The macros of the workspace called in an item, in a body or an initializer (D117, #367): which are found, in what
 * order, by what key, and what the macro server is asked.
 */
@Test
class BodyMacroCallTest {
    @TestCase
    func callsInAnItemGoBeforeTheCallsOnItInnermostFirst() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @A class X {
                func f(): Int64 { @B(@I(1)) }
                let y = @I(2)
            }
            "#)

        // act
        let calls = serverCalls(db, file).map {one => describeCall(db, one)}

        // assert: `y`'s `@I` is the first of its own item
        @Expect(calls, ["I0/", "B0/", "I0/", "A0!"])
    }

    @TestCase
    func aCallIsKeyedByItsItemItsMacrosNameAndItsOrdinalAmongTheCallsOfThatName() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            func f(): Unit {
                @B(1)
                @I(2)
                @B(3)
            }
            "#)

        // act
        let keys = serverCalls(db, file).map {one => macroCallKeyOf(db, one.call)}

        // assert
        @Expect(keys.map {key => "${key.inBody ?? "-"}#${key.index}"}, ["B#0", "I#0", "B#1"])
        @Expect(keys.map {key => macroCallOf(db, file, key)}, serverCalls(db, file).map {one => Some(one.call)})
    }

    @TestCase
    func aKeyFindsItsCallAfterAnEditElsewhereAndNoneOnceItIsGone() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            func f(): Unit {
                @B(1)
            }
            "#)
        let call = serverCalls(db, file)[0].call
        let key = macroCallKeyOf(db, call)

        // act
        db.setFileText(file.fileId(db), Rope("// a comment\n" + file.text(db).toString()))
        let afterEdit = macroCallOf(db, file, key)
        db.setFileText(file.fileId(db), Rope(file.text(db).toString().replace("@B(1)", "1")))
        let afterRemoval = macroCallOf(db, file, key)

        // assert
        @Expect(afterEdit, Some(call))
        @Expect(afterRemoval, None<MacroCallId>)
    }

    @TestCase
    func theInputIsWhatTheParenthesesHoldAndTheParentsTheCallsAroundIt() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @A class X {
                @I func f(): Int64 { @M[x](1 + 2) }
            }
            "#)

        // act
        let requests = macroRequests(db, file).map {request => describe(request)}

        // assert
        @Expect(requests[0], "M[x] <1 + 2> parents=A,I children=")
    }

    @TestCase
    func aCallWithAnotherInItsInputIsNotAskedUntilNestingIsExpanded() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            func f(): Int64 { @B(@I(1)) }
            "#)

        // act
        let requests = macroRequests(db, file).map {request => describe(request)}

        // assert
        @Expect(requests, ["I <1> parents=B children="])
    }

    @TestCase
    func aCallOnALocalDeclarationIsGivenTheDeclaration() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            func f(): Unit {
                @I func local() {}
            }
            "#)

        // act
        let requests = macroRequests(db, file).map {request => describe(request)}

        // assert
        @Expect(requests, ["I <func local() {}> parents= children="])
    }

    @TestCase
    func aCallUnderAFalseWhenOrOfStdIsNotAsked() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            import std.unittest.testmacro.*
            func f(): Unit {
                @When[os == "Windows"]
                func local(): Int64 { @B(1) }
                @Expect(1, 1)
                @I(2)
            }
            "#, std: ["std.unittest", "std.unittest.testmacro"], cfg: "os:Linux")

        // act
        let calls = serverCalls(db, file).map {one => describeCall(db, one)}

        // assert
        @Expect(calls, ["I0/"])
    }

    @TestCase
    func anAnswerMakesTheRequestCurrentAndItsDiagnosticsAreOnTheCallsHead() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            func f(): Int64 { @B(1) }
            "#)
        let request = requestNamed(db, file, "B")
        let output = MacroOutput(request.fingerprint, MappedText("(1) + 0", []), [],
            [MacroDiagnostic(MacroSeverity.MacroError, None, "not a number", "")])

        // act
        setMacroOutputs(db, [(request.call, output)])
        let diagnostics = macroDiagnostics(db, file)

        // assert
        @Expect(pendingMacroRequests(db, file).size, 0)
        let text = file.text(db).toString()
        @Expect(diagnostics.map {one => text[one.range.start..one.range.end]}, ["@B"])
    }
}

@Test
class BodyMacroExpansionTest {
    @TestCase
    func anExpressionIsTypedFromItsCurrentExpansion() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            func f(): Unit { let x = @B(1 + 2) }
            "#, std: ["std.core"])
        let request = requestNamed(db, file, "B")
        let def = DefId(db, ItemFile.Source(file), named(itemTree(db, file).items, "f").id)
        @Expect(inferBody(db, def).locals[0].kind(db), TyKind.TodoTy(Todo.MacroCall))

        // act
        setMacroOutputs(db, [(request.call, writtenOutput(request, "true"))])
        let lowered = bodyWithSourceMap(db, def)
        let inferred = inferBody(db, def)

        // assert
        @Expect(inferred.locals[0].text(db), "Bool")
        let expanded = lowered.sourceMap.exprs.filterMap {one => one.written}.filter {one => one.expansion == request.call}
        @Expect(expanded.size, 1)
        @Expect(expanded[0].node(db, def.file(db)).getOrThrow().text(), "true")
        @Expect(lowered.sourceMap.exprAtSource(expanded[0]).isSome())
        let syntax = bodyCallNodeOf(db, request.call).getOrThrow()
        @Expect(lowered.sourceMap.exprAt(SyntaxNodePtr(syntax)), lowered.sourceMap.exprAtSource(expanded[0]))
    }

    @TestCase
    func statementExpansionsDeclareNamesInTheSurroundingBlock() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            func f(seed: Int64): Int64 {
                @B(nothing)
                let result = made
                result
            }
            "#, std: ["std.core"])
        let request = requestNamed(db, file, "B")
        setMacroOutputs(db, [(request.call, writtenOutput(request,
            "func local(): Int64 { seed }\nlet made = local()"))])
        let def = DefId(db, ItemFile.Source(file), named(itemTree(db, file).items, "f").id)

        // act
        let lowered = body(db, def)
        let inferred = inferBody(db, def)

        // assert
        @Expect(lowered.locals.map {one => one.name}, ["seed", "local", "made", "result"])
        @Expect(inferred.locals.map {one => one.text(db)}, ["Int64", "() -> Int64", "Int64", "Int64"])
        @Expect(inferred.diagnostics.size, 0)
    }

    @TestCase
    func twoOutputsAtTheSameOffsetsHaveDifferentSources() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            func f(): Unit { let a = @B(0); let b = @I(0) }
            "#, std: ["std.core"])
        let first = requestNamed(db, file, "B")
        let second = requestNamed(db, file, "I")
        setMacroOutputs(db, [(first.call, writtenOutput(first, "1")), (second.call, writtenOutput(second, "2"))])
        let def = DefId(db, ItemFile.Source(file), named(itemTree(db, file).items, "f").id)

        // act
        let map = bodyWithSourceMap(db, def).sourceMap
        let sources = map.exprs.filterMap {one => one.written}.filter {one => one.expansion.isSome()}

        // assert
        @Expect(sources.size, 2)
        @Expect(sources[0].ptr, sources[1].ptr)
        @Expect(map.exprAtSource(sources[0]) != map.exprAtSource(sources[1]))
        @Expect(map.exprAt(sources[0].ptr), None<ExprId>)
    }

    @TestCase
    func anEditMakesTheOldExpressionExpansionUnread() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            func f(): Unit { let x = @B(1) }
            "#, std: ["std.core"])
        let request = requestNamed(db, file, "B")
        setMacroOutputs(db, [(request.call, writtenOutput(request, "true"))])
        let def = DefId(db, ItemFile.Source(file), named(itemTree(db, file).items, "f").id)
        @Expect(inferBody(db, def).locals[0].text(db), "Bool")

        // act
        db.setFileText(file.fileId(db), Rope(file.text(db).toString().replace("@B(1)", "@B(2)")))

        // assert
        @Expect(inferBody(db, def).locals[0].kind(db), TyKind.TodoTy(Todo.MacroCall))
        @Expect(bodyWithSourceMap(db, def).sourceMap.exprs.filterMap {one => one.written}.iterator().all {one => one.expansion.isNone()})
    }
    @TestCase
    func aFailedRunDoesNotReadTheRetainedExpressionOutput() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            func f(): Unit { let x = @B(1) }
            "#, std: ["std.core"])
        let request = requestNamed(db, file, "B")
        setMacroOutputs(db, [(request.call, writtenOutput(request, "true"))])
        let def = DefId(db, ItemFile.Source(file), named(itemTree(db, file).items, "f").id)
        @Expect(inferBody(db, def).locals[0].text(db), "Bool")

        // act
        setMacroOutputs(db, [(request.call, MacroOutput(request.fingerprint, None, [],
            [MacroDiagnostic(MacroSeverity.MacroError, None, "failed", "")]))])

        // assert
        @Expect(macroOutputOf(db, request.call).getOrThrow().expansion.isSome())
        @Expect(inferBody(db, def).locals[0].kind(db), TyKind.TodoTy(Todo.MacroCall))
    }

    @TestCase
    func aMacroOnALocalDeclarationReplacesItWithStatements() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            func f(): Int64 {
                @B func old(): Bool { true }
                made
            }
            "#, std: ["std.core"])
        let request = requestNamed(db, file, "B")
        setMacroOutputs(db, [(request.call, writtenOutput(request, "let made = 1"))])
        let def = DefId(db, ItemFile.Source(file), named(itemTree(db, file).items, "f").id)

        // act
        let lowered = body(db, def)
        let inferred = inferBody(db, def)

        // assert
        @Expect(lowered.locals.map {one => one.name}, ["made"])
        @Expect(inferred.locals[0].text(db), "Int64")
        @Expect(inferred.diagnostics.size, 0)
    }

    @TestCase
    func speculativeLoweringReadsNoExpansion() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            func f(): Unit { let x = @B(1) }
            "#, std: ["std.core"])
        let request = requestNamed(db, file, "B")
        setMacroOutputs(db, [(request.call, writtenOutput(request, "true"))])
        let def = DefId(db, ItemFile.Source(file), named(itemTree(db, file).items, "f").id)
        let decl = Decl.cast(itemIdMap(db, file).node(def.item(db), parse(db, file).syntaxNode()).getOrThrow()).getOrThrow()

        // act
        let speculative = lowerBody(decl)

        // assert
        @Expect(speculative.sourceMap.exprs.filterMap {one => one.written}.all {one => one.expansion.isNone()})
        @Expect(speculative.body.exprs.any {one => if (let MacroExpr(_) <- one) { true } else { false }})
    }

    @TestCase
    func patternsLocalsAndTypesAreQualifiedByTheirExpansion() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            func f(): Unit {
                if (true) { @B(0) } else { @I(0) }
            }
            "#, std: ["std.core"])
        let first = requestNamed(db, file, "B")
        let second = requestNamed(db, file, "I")
        setMacroOutputs(db, [(first.call, writtenOutput(first, "let made: Int64 = 1")),
            (second.call, writtenOutput(second, "let made: Int64 = 2"))])
        let def = DefId(db, ItemFile.Source(file), named(itemTree(db, file).items, "f").id)

        // act
        let map = bodyWithSourceMap(db, def).sourceMap

        // assert
        for (sources in [map.pats, map.locals, map.types]) {
            let present = sources.filterMap {one => one.written}
            @Expect(present.size, 2)
            @Expect(present[0].ptr, present[1].ptr)
            @Expect(present[0].expansion, Some(first.call))
            @Expect(present[1].expansion, Some(second.call))
        }
        @Expect(map.patAtSource(map.pats[0].written.getOrThrow()) != map.patAtSource(map.pats[1].written.getOrThrow()))
        @Expect(map.localAtSource(map.locals[0].written.getOrThrow()) != map.localAtSource(map.locals[1].written.getOrThrow()))
        @Expect(map.typeAtSource(map.types[0].written.getOrThrow()) != map.typeAtSource(map.types[1].written.getOrThrow()))
        @Expect(inferBody(db, def).diagnostics.size, 0)
    }

    @TestCase
    func initializersAndParameterDefaultsReadTheirExpansions() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            let value = @B(0)
            func f(arg: Int64 = @I(0)): Int64 { arg }
            "#, std: ["std.core"])
        let initializer = requestNamed(db, file, "B")
        let defaultValue = requestNamed(db, file, "I")
        setMacroOutputs(db, [(initializer.call, writtenOutput(initializer, "true")),
            (defaultValue.call, writtenOutput(defaultValue, "2"))])
        let value = DefId(db, ItemFile.Source(file), named(itemTree(db, file).items, "value").id)
        let f = DefId(db, ItemFile.Source(file), named(itemTree(db, file).items, "f").id)

        // act
        let valueTy = declaredTyOf(db, value)
        let expr = body(db, f).params[0].defaultValue.getOrThrow()
        let inferred = inferBody(db, f)

        // assert
        @Expect(valueTy.text(db), "Bool")
        @Expect(inferred[expr].getOrThrow().text(db), "Int64")
        @Expect(inferred.diagnostics.size, 0)
    }

}
