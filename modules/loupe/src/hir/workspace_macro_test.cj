package loupe.hir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange
import rope.Rope
import loupe.db.*
import loupe.fixture.*

/**
 * The macros of the workspace the tests call, in a package of their own.
 */
let WORKSPACE_MACROS = #"
    //- /ms/ms.cj module=m package=m.ms
    macro package m.ms
    import std.ast.*
    public macro A(input: Tokens): Tokens { input }
    public macro B(input: Tokens): Tokens { input }
    public macro I(input: Tokens): Tokens { input }
    public macro M(attrs: Tokens, input: Tokens): Tokens { input }
    "#

/**
 * The database of `text`, the text of `/main.cj` in package `m`, with the macros of `WORKSPACE_MACROS` and std's
 * packages `std` read from the SDK, and its file.
 */
func workspaceMacroDatabase(text: String, std!: Array<String> = []): (AnalysisDatabase, SourceFile, Fixture) {
    let indented = trimIndent(text).split("\n").map {line => "    " + line}
    let parsed = Fixture.parse("\n    //- /main.cj module=m package=m\n" + String.join(indented, delimiter: "\n") +
        "\n" + WORKSPACE_MACROS)
    let db = parsed.database(binaries: std.map {name => stdCjoRead(name, stdCjo(name))})
    let file = db.sourceFile(parsed.file("/main.cj").fileId).getOrThrow()
    (db, file, parsed)
}

/**
 * A request as a line: the macro, its attribute, its input, its parents and its children.
 */
func describe(request: MacroRequest): String {
    let attrs = request.attrs.map {one => "[${one.text}]"} ?? ""
    let parents = String.join(request.parents, delimiter: ",")
    let children = String.join(request.children.map {child => "${child.name}${child.items}"}, delimiter: ",")
    "${request.definition.name}${attrs} <${request.input.text}> parents=${parents} children=${children}"
}

/**
 * An output of `text` all of which the macro wrote.
 */
func writtenOutput(request: MacroRequest, text: String, items!: Array<MacroItem> = []): MacroOutput {
    MacroOutput(request.fingerprint, MappedText(text, [MappedSpan(TextRange.at(0, text.size), SpanOrigin.FromCall)]),
        items, [])
}

/**
 * The request of `file` for the macro `name`.
 */
func requestNamed(db: AnalysisDatabase, file: SourceFile, name: String): MacroRequest {
    for (request in macroRequests(db, file) where request.definition.name == name) {
        return request
    }
    throw FixtureException("no request for ${name}")
}

/**
 * The calls of the workspace's macros (#176): which, in what order, and what the macro server is asked.
 */
@Test
class WorkspaceMacroRequestTest {
    @TestCase
    func callsAreInTheOrderCjcExpandsThemAndOnlyTheOutermostIsRead() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @A @B class X {
                @I func f() {}
            }
            "#)

        // act
        let calls = workspaceCalls(db, file)

        // assert
        @Expect(calls.map {one => "${one.definition.name}${one.call.index(db)}${if (one.read) {"!"} else {""}}"},
            ["I0", "B1", "A0!"])
    }

    @TestCase
    func theInputIsTheDeclarationAfterTheCallAndTheAttributeWhatTheBracketsHold() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @M[x, 1]
            class C { let a = 1 }
            "#)

        // act
        let requests = macroRequests(db, file).map {request => describe(request)}

        // assert
        @Expect(requests, ["M[x, 1] <class C { let a = 1 }> parents= children="])
    }

    @TestCase
    func anAttributeHoldsTheBracketsNestedInIt() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @M[rename: "x", payload: ["key"]]
            class C {}
            "#)

        // act
        let requests = macroRequests(db, file).map {request => describe(request)}

        // assert
        @Expect(requests, [#"M[rename: "x", payload: ["key"]] <class C {}> parents= children="#])
    }

    @TestCase
    func argumentsThatAreTokensHoldTheParenthesesNestedInThem() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @A(x y (z) w)
            "#)

        // act
        let requests = macroRequests(db, file).map {request => describe(request)}

        // assert
        @Expect(requests, ["A <x y (z) w> parents= children="])
    }

    @TestCase
    func theInputComesFromTheSourceRelativeToTheTopLevelItem() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @M[x]
            class C {}
            "#)

        // act
        let request = macroRequests(db, file)[0]

        // assert
        @Expect(request.input.spans.map {span => span.toString()}, ["0..10 <- FromSource(6..16)"])
        @Expect(request.attrs?.spans.map {span => span.toString()}, Some(["0..1 <- FromSource(3..4)"]))
    }

    @TestCase
    func anOuterCallWaitsForTheOutputOfTheInnerOne() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @A @B class X {}
            "#)

        // act
        let before = macroRequests(db, file).map {request => describe(request)}
        let inner = requestNamed(db, file, "B")
        setMacroOutputs(db, [(inner.call, writtenOutput(inner, "class X {}\nclass Y {}",
            items: [MacroItem("note", MacroItemValue.StringItem("from B"))]))])
        let after = macroRequests(db, file).map {request => describe(request)}

        // assert
        @Expect(before, ["B <class X {}> parents=A children="])
        @Expect(after, ["B <class X {}> parents=A children=", "A <class X {}\nclass Y {}> parents= children=B[note=String(from B)]"])
        @Expect(requestNamed(db, file, "A").input.spans.map {span => span.toString()},
            ["0..21 <- FromSource(3..5)"])
    }

    @TestCase
    func aCallOnAMemberIsItsOutputInTheInputOfTheCallOnItsType() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @A
            class Y {
                @I func f() {}
            }
            "#)

        // act
        let inner = requestNamed(db, file, "I")
        setMacroOutputs(db, [(inner.call, writtenOutput(inner, "func added() {}\nfunc f() {}"))])
        let requests = macroRequests(db, file).map {request => describe(request)}

        // assert
        @Expect(requests, ["I <func f() {}> parents=A children=",
            "A <class Y {\n    func added() {}\nfunc f() {}\n}> parents= children=I[]"])
    }

    @TestCase
    func aCallWhoseInnerCallsMacroIsOfStdKeepsItsText() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @A @Other[x] class X {}
            "#)

        // act
        let requests = macroRequests(db, file).map {request => describe(request)}

        // assert
        @Expect(requests, ["A <@Other[x] class X {}> parents= children="])
    }

    @TestCase
    func anOuterCallIsGivenWhatTheCallsNestedInItsInnerCallSet() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @A
            @B
            class Y {
                @I func f() {}
            }
            "#)
        let member = requestNamed(db, file, "I")
        setMacroOutputs(db, [(member.call, writtenOutput(member, "func f() {}",
            items: [MacroItem("note", MacroItemValue.StringItem("from I"))]))])
        let inner = requestNamed(db, file, "B")
        setMacroOutputs(db, [(inner.call, writtenOutput(inner, "class Y {}"))])

        // act
        let outer = describe(requestNamed(db, file, "A"))

        // assert: as `@DeriveExt` reads `@Serde` of an enum's variants past `@Serde` on the enum
        @Expect(outer, "A <class Y {}> parents= children=I[note=String(from I)],B[]")
    }

    @TestCase
    func aDeriveOfStdInTheInputIsItsDeclarationAndTheExtendsItAddsAfterIt() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import std.deriving.*
            import m.ms.*
            @A
            @Derive[Equatable]
            class X {}
            "#, std: ["std.core", "std.deriving"])

        // act
        let requests = macroRequests(db, file).map {request => describe(request)}

        // assert
        @Expect(requests, ["A <class X {}\nextend X <: Equatable<X> {\n    public operator func ==(other: X): Bool ${stubOf("@Derive")}\n" +
            "    public operator func !=(other: X): Bool ${stubOf("@Derive")}\n}\n> parents= children="])
    }

    @TestCase
    func aRequestIsPendingUntilAnOutputAnswersItAndAgainOnceItsItemChanges() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @A class X {}
            "#)
        let request = macroRequests(db, file)[0]

        // act
        let before = pendingMacroRequests(db, file).size
        setMacroOutputs(db, [(request.call, writtenOutput(request, "class X {}"))])
        let answered = pendingMacroRequests(db, file).size
        db.setFileText(file.fileId(db), Rope(file.text(db).toString().replace("class X {}", "class X { let a = 1 }")))
        let edited = pendingMacroRequests(db, file).map {one => one.input.text}

        // assert
        @Expect(before, 1)
        @Expect(answered, 0)
        @Expect(edited, ["class X { let a = 1 }"])
    }
}

/**
 * What the macro server answered for a call (#176), as the analysis reads it.
 */
@Test
class WorkspaceMacroExpansionTest {
    @TestCase
    func anExpansionReplacesItsItemInThePackagesScope() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @A class C {}
            "#)
        let request = macroRequests(db, file)[0]
        let pkg = packageOfFile(db, file).getOrThrow()
        let c = DefId(db, ItemFile.Source(file), itemTree(db, file).items[0].id)

        // act
        let unreadBefore = hasUnreadMacros(db, c)
        setMacroOutputs(db, [(request.call, writtenOutput(request, "class C {}\nfunc generated(): Int64 { 1 }"))])
        let names = defMapAt(db, PackageRef.Source(pkg), ScopeStage.Expanded).names
        let cs = names.get("C") ?? []

        // assert
        @Expect(unreadBefore, true)
        @Expect(hasUnreadMacros(db, c), false)
        @Expect(names.contains("generated"), true)
        @Expect(cs.size, 1)
        @Expect(cs.iterator().all {def => def.id.file(db) == ItemFile.Expansion(request.call)}, true)
    }

    @TestCase
    func aDeriveOfStdInTheInputOfAnAnsweredCallIsReadInItsOutputAlone() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import std.deriving.*
            import m.ms.*
            @A
            @Derive[Equatable]
            class X {}
            "#, std: ["std.core", "std.deriving"])
        let request = macroRequests(db, file)[0]

        // act
        let before = expandedCalls(db, file).size
        setMacroOutputs(db, [(request.call, MacroOutput(request.fingerprint, request.input, [], []))])

        // assert
        @Expect(before, 1)
        @Expect(expandedCalls(db, file), [request.call])
    }

    @TestCase
    func noOutputLeavesTheItemAsWritten() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @A class C {}
            "#)
        let pkg = packageOfFile(db, file).getOrThrow()

        // act
        let cs = defMapAt(db, PackageRef.Source(pkg), ScopeStage.Expanded).names.get("C") ?? []

        // assert
        @Expect(expandedCalls(db, file).size, 0)
        @Expect(cs.map {def => def.id.file(db) == ItemFile.Source(file)}, [true])
    }

    @TestCase
    func aRunThatFailsKeepsTheLastExpansionAndReportsItsOwnDiagnostics() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @A class C {}
            "#)
        let request = macroRequests(db, file)[0]
        setMacroOutputs(db, [(request.call, writtenOutput(request, "class C {}\nfunc generated() {}"))])
        let failure = MacroOutput(request.fingerprint + 1, None, [],
            [MacroDiagnostic(MacroSeverity.MacroError, None, "no", "")])

        // act
        setMacroOutputs(db, [(request.call, failure)])
        let output = macroOutputOf(db, request.call).getOrThrow()

        // assert
        @Expect(macroExpansion(db, request.call).text, "class C {}\nfunc generated() {}")
        @Expect(output.fingerprint, request.fingerprint + 1)
        @Expect(output.diagnostics.size, 1)
    }

    @TestCase
    func aNameCopiedFromTheSourceIsWhereTheSourceWritesItAndOneTheMacroWroteIsTheCall() {
        // arrange
        let (db, file, parsed) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @M[x]
            class C {}
            "#)
        let request = macroRequests(db, file)[0]
        let text = "class C {}\nfunc generated() {}"
        let output = MacroOutput(request.fingerprint, MappedText(text, [
            MappedSpan(TextRange(0, 10), SpanOrigin.FromSource(TextRange(6, 16))),
            MappedSpan(TextRange(11, text.size), SpanOrigin.FromCall)
        ]), [], [])
        setMacroOutputs(db, [(request.call, output)])
        let items = expansionItemTree(db, request.call).items
        let source = parsed.file("/main.cj").text
        let anchor = source.indexOf("@M").getOrThrow()

        // act
        let copied = expansionOrigin(db, request.call, items[0].id)
        let written = expansionOrigin(db, request.call, items[1].id)

        // assert
        let c = source.indexOf("C {}").getOrThrow()
        @Expect(copied.map {pair => pair[0]}, Some(TextRange(c, c + 1)))
        @Expect(written.map {pair => pair[0]}, Some(TextRange(anchor, anchor + 5)))
        @Expect(written.map {pair => pair[1].start}, Some(anchor))
    }
}

/**
 * What changes a request besides its text, and what the macros report (#176's step 3).
 */
@Test
class WorkspaceMacroLibraryTest {
    @TestCase
    func aNewLibraryOfTheMacroMakesTheRequestNew() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @A class C {}
            "#)
        let request = macroRequests(db, file)[0]
        setMacroOutputs(db, [(request.call, writtenOutput(request, "class C {}"))])

        // act
        request.definition.pkg.setMacroLibrary(db).to(7)

        // assert
        @Expect(pendingMacroRequests(db, file).map {one => one.definition.name}, ["A"])
    }

    @TestCase
    func whatAMacroReportsIsWhereItsOriginIsInTheSourceElseOnTheCall() {
        // arrange
        let (db, file, parsed) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @M[x]
            class C {}
            "#)
        let request = macroRequests(db, file)[0]
        let output = MacroOutput(request.fingerprint, None, [], [
            MacroDiagnostic(MacroSeverity.MacroError, SpanOrigin.FromSource(TextRange(12, 13)), "bad name", "rename it"),
            MacroDiagnostic(MacroSeverity.MacroWarning, None, "odd", "")
        ])
        setMacroOutputs(db, [(request.call, output)])
        let source = parsed.file("/main.cj").text
        let anchor = source.indexOf("@M").getOrThrow()

        // act
        let found = macroDiagnostics(db, file)

        // assert
        let c = source.indexOf("C {}").getOrThrow()
        @Expect(found, [
            MacroCallDiagnostic(TextRange(c, c + 1), MacroSeverity.MacroError, "bad name: rename it"),
            MacroCallDiagnostic(TextRange(anchor, anchor + 5), MacroSeverity.MacroWarning, "odd")
        ])
    }

    @TestCase
    func anOutputForAnOlderRequestReportsNothing() {
        // arrange
        let (db, file, _) = workspaceMacroDatabase(#"
            package m
            import m.ms.*
            @A class C {}
            "#)
        let request = macroRequests(db, file)[0]
        let output = MacroOutput(request.fingerprint + 1, None, [],
            [MacroDiagnostic(MacroSeverity.MacroError, None, "stale", "")])

        // act
        setMacroOutputs(db, [(request.call, output)])

        // assert
        @Expect(macroDiagnostics(db, file).size, 0)
    }
}
