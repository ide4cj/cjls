package loupe.hir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange
import rope.Rope
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
