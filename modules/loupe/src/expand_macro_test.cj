package loupe

import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange
import rope.Rope
import loupe.db.*
import loupe.fixture.*
import loupe.hir.*

/**
 * The database of `parsed` with std.core's and std.deriving's `.cjo`s.
 */
func deriveDatabase(parsed: Fixture): AnalysisDatabase {
    parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core")),
        stdCjoRead("std.deriving", stdCjo("std.deriving"))])
}

/**
 * Checks the macro call at the cursor of `fixture` is its annotation: the head of the call there, and the name of
 * the call read for it; none if there is none.
 */
func checkMacroCallAt(fixture: String): Unit {
    let parsed = Fixture.parse(fixture)
    let db = deriveDatabase(parsed)
    let cursor = parsed.cursor ?? throw FixtureException("no $0 in the fixture")
    let annotations = match (macroCallAt(db, cursor.fileId, cursor.offset)) {
        case Some(at) => [Annotation(cursor.fileId, at.range, "call ${expandedMacro(db, at.call)?.name ?? "none"}")]
        case None => Array<Annotation>()
    }
    expectAnnotations(fixture, annotations)
}

/**
 * Where `target` is, as a line: its file and its name's range, and whether in an expansion.
 */
func placeOf(target: NavigationTarget): String {
    let inExpansion = if (target.expansion.isSome()) {
        " in expansion"
    } else {
        ""
    }
    "${target.fileId} ${target.focusRange}${inExpansion}"
}

/**
 * The macros of the workspace the tests call, in a package of their own.
 */
let EXPANSION_MACROS = #"
    //- /ms/ms.cj module=m package=m.ms
    macro package m.ms
    import std.ast.*
    public macro A(input: Tokens): Tokens { input }
    public macro B(input: Tokens): Tokens { input }
    public macro M(attrs: Tokens, input: Tokens): Tokens { input }
    "#

/**
 * The database of `text`, the text of `/main.cj` in package `m` with the macros of `EXPANSION_MACROS`, and its file.
 */
func expansionDatabase(text: String): (AnalysisDatabase, SourceFile) {
    let indented = trimIndent(text).split("\n").map {line => "    " + line}
    let parsed = Fixture.parse("\n    //- /main.cj module=m package=m\n" + String.join(indented, delimiter: "\n") +
        "\n" + EXPANSION_MACROS)
    let db = parsed.database()
    (db, db.sourceFile(parsed.file("/main.cj").fileId).getOrThrow())
}

/**
 * The request of `file` for the macro `name`.
 */
func requestFor(db: AnalysisDatabase, file: SourceFile, name: String): MacroRequest {
    for (request in macroRequests(db, file) where request.definition.name == name) {
        return request
    }
    throw FixtureException("no request for ${name}")
}

/**
 * Answers the request of `file` for `name` by `text`, `spans` where it comes from.
 */
func answer(db: AnalysisDatabase, file: SourceFile, name: String, text: String, spans: Array<MappedSpan>): MacroCallId {
    let request = requestFor(db, file, name)
    setMacroOutputs(db, [(request.call, MacroOutput(request.fingerprint, MappedText(text, spans), [], []))])
    request.call
}

/**
 * `@M[x] class C {}` answered by an output copying `class C {}` and writing a class `Gen` and a function `make`.
 */
func answeredM(): (AnalysisDatabase, SourceFile, MacroCallId, String) {
    let (db, file) = expansionDatabase(#"
        package m
        import m.ms.*
        @M[x]
        class C {}
        "#)
    let text = "class C {}\nclass Gen {}\nfunc make<T>(g: Gen, t: T): C { C() }"
    let call = answer(db, file, "M", text, [
        MappedSpan(TextRange(0, 10), SpanOrigin.FromSource(TextRange(6, 16))),
        MappedSpan(TextRange(11, text.size), SpanOrigin.FromCall)
    ])
    (db, file, call, text)
}

/**
 * The offset of the `n`th `what` in `text`, from 0, plus `plus`.
 */
func offsetIn(text: String, what: String, n!: Int64 = 0, plus!: Int64 = 0): Int64 {
    var at = text.indexOf(what).getOrThrow()
    for (_ in 0..n) {
        at = text.indexOf(what, at + 1).getOrThrow()
    }
    at + plus
}

/**
 * The macro call at a position, and what it expands to.
 */
@Test
class MacroCallAtTest {
    @TestCase
    func theNameOfAStdDeriveIsItsCall() {
        checkMacroCallAt(#"
            //- /main.cj module=m package=m
              package m
              import std.deriving.*
              @Der$0ive[Hashable, Equatable]
            //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ call @Derive
              struct S {}
            "#)
    }

    @TestCase
    func insideTheAttributeOfAStdDeriveIsItsCall() {
        checkMacroCallAt(#"
            //- /main.cj module=m package=m
              package m
              import std.deriving.*
              @Derive[Hashable, Equ$0atable]
            //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ call @Derive
              struct S {}
            "#)
    }

    @TestCase
    func aMacroTheAnalysisDoesNotExpandIsTheCallOfTheItemAroundIt() {
        checkMacroCallAt(#"
            //- /main.cj module=m package=m
              package m
              import std.deriving.*
              @Derive[Hashable]
            //^^^^^^^^^^^^^^^^^ call @Derive
              struct S {
                  @DeriveExc$0lude
                  let x: Int64 = 0
              }
            "#)
    }

    @TestCase
    func theDeclarationUnderACallIsTheCall() {
        checkMacroCallAt(#"
            //- /main.cj module=m package=m
              package m
              import std.deriving.*
              @Derive[Hashable]
            //^^^^^^^^^^^^^^^^^ call @Derive
              struct $0S {}
            "#)
    }

    @TestCase
    func aBodyInTheItemIsItsCall() {
        checkMacroCallAt(#"
            //- /main.cj module=m package=m
              package m
              import std.deriving.*
              @Derive[Hashable]
            //^^^^^^^^^^^^^^^^^ call @Derive
              struct S {
                  func f(): Int64 { $01 }
              }
            "#)
    }

    @TestCase
    func aBodyIsNoCallWhenBodiesAreLeftOut() {
        // arrange
        let fixture = #"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Hashable]
            struct S {
                func f(): Int64 { 1 }
            }
            "#
        let parsed = Fixture.parse(fixture)
        let db = deriveDatabase(parsed)
        let file = parsed.file("/main.cj")

        // act
        let inBody = macroCallAt(db, file.fileId, offsetIn(file.text, "1 }"), inBody: false)
        let onMember = macroCallAt(db, file.fileId, offsetIn(file.text, "f()"), inBody: false)

        // assert
        @Expect(inBody, None<MacroCallAt>)
        @Expect(onMember.isSome())
    }

    @TestCase
    func outsideAnyItemWithACallIsNoCall() {
        checkMacroCallAt(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Hashable]
            struct S {}
            func $0f() {}
            "#)
    }

    @TestCase
    func anInnerCallOfTheWorkspaceIsTheCallReadOnItsItemPositionedAtItsOutput() {
        // arrange
        let (db, file) = expansionDatabase(#"
            package m
            import m.ms.*
            @A @B class X {}
            "#)
        // relative to `@A`: `@B` is 3..5
        let inner = answer(db, file, "B", "class X {}\nclass Y {}", [MappedSpan(TextRange(0, 21), SpanOrigin.FromCall)])
        let read = answer(db, file, "A", "class X {}\nclass Y {}", [MappedSpan(TextRange(0, 21),
            SpanOrigin.FromSource(TextRange(3, 5)))])
        let source = file.text(db).toString()
        let b = offsetIn(source, "@B", plus: 1)

        // act
        let at = macroCallAt(db, file.fileId(db), b)
        let onRead = macroCallAt(db, file.fileId(db), offsetIn(source, "@A"))

        // assert
        @Expect(at?.call, Some(read))
        @Expect(at?.range, Some(TextRange(b - 1, b + 1)))
        @Expect(at?.focus, Some(TextRange(0, 21)))
        @Expect(onRead?.call, Some(read))
        @Expect(onRead?.focus, None<TextRange>)
        @Expect(expandedMacro(db, inner), None<ExpandedMacro>)
    }

    @TestCase
    func aCallOfTheWorkspaceNotAnsweredIsReadButHasNoExpansion() {
        // arrange
        let (db, file) = expansionDatabase(#"
            package m
            import m.ms.*
            @M[x]
            class C {}
            "#)
        let source = file.text(db).toString()

        // act
        let at = macroCallAt(db, file.fileId(db), offsetIn(source, "x]"))

        // assert
        @Expect(at.isSome())
        @Expect(expandedMacro(db, at.getOrThrow().call), None<ExpandedMacro>)
    }

    @TestCase
    func aStdDeriveExpandsToTheAnalysissSignatures() {
        // arrange
        let fixture = #"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Hashable]
            struct S {}
            "#
        let parsed = Fixture.parse(fixture)
        let db = deriveDatabase(parsed)
        let file = parsed.file("/main.cj")
        let at = macroCallAt(db, file.fileId, offsetIn(file.text, "Derive")).getOrThrow()

        // act
        let expanded = expandedMacro(db, at.call).getOrThrow()

        // assert
        @Expect(expanded.name, "@Derive")
        @Expect(expanded.kind, ExpansionKind.StdExpansion)
        @Expect(expanded.range, at.range)
        @Expect(expanded.text, macroExpansion(db, at.call).text)
        @Expect(expanded.text.contains("extend S <: Hashable"))
        @Expect(expanded.declaration, Some("struct S {}"))
    }

    @TestCase
    func aWorkspaceMacroExpandsToTheServersOutput() {
        // arrange
        let (db, file, call, text) = answeredM()

        // act
        let expanded = expandedMacro(db, call).getOrThrow()

        // assert
        @Expect(expanded.name, "@M")
        @Expect(expanded.kind, ExpansionKind.WorkspaceExpansion)
        @Expect(expanded.text, text)
        @Expect(file.text(db).toString()[expanded.range.start..expanded.range.end], "@M[x]")
    }

    @TestCase
    func aWorkspaceCallInABodyExpandsToTheServersOutputFromItsHead() {
        // arrange
        let (db, file) = expansionDatabase(#"
            package m
            import m.ms.*
            @A
            func f(): Int64 { @B(1 + 2) }
            "#)
        let call = answer(db, file, "B", "(1 + 2) * 10", [MappedSpan(TextRange(0, 12), SpanOrigin.FromCall)])
        let source = file.text(db).toString()

        // act
        let onHead = macroCallAt(db, file.fileId(db), offsetIn(source, "B("))
        let inArguments = macroCallAt(db, file.fileId(db), offsetIn(source, "2)"))
        let leavingBodiesOut = macroCallAt(db, file.fileId(db), offsetIn(source, "B("), inBody: false)

        // assert
        @Expect(onHead.map {at => at.call}, Some(call))
        @Expect(onHead.map {at => source[at.range.start..at.range.end]}, Some("@B"))
        let expanded = expandedMacro(db, call).getOrThrow()
        @Expect(expanded.name, "@B")
        @Expect(expanded.kind, ExpansionKind.WorkspaceExpansion)
        @Expect(expanded.text, "(1 + 2) * 10")
        @Expect(inArguments.map {at => at.call} == Some(call), false)
        @Expect(leavingBodiesOut.map {at => at.call} == Some(call), false)
    }

    @TestCase
    func aWorkspaceCallInABodyNotAnsweredHasNoExpansion() {
        // arrange
        let (db, file) = expansionDatabase(#"
            package m
            import m.ms.*
            func f(): Int64 { @B(1) }
            "#)
        let source = file.text(db).toString()

        // act
        let at = macroCallAt(db, file.fileId(db), offsetIn(source, "@B")).getOrThrow()

        // assert
        @Expect(at.call.inBody(db), Some("B"))
        @Expect(expandedMacro(db, at.call), None<ExpandedMacro>)
    }

    @TestCase
    func aKeyFindsItsCallAfterAnEditElsewhere() {
        // arrange
        let (db, file, call, _) = answeredM()
        let key = macroCallKeyOf(db, call)

        // act
        db.setFileText(file.fileId(db), Rope("// a comment\n" + file.text(db).toString()))
        let found = macroCallOf(db, file, key)
        let wrong = macroCallOf(db, file, MacroCallKey(key.item, 1))

        // assert
        @Expect(found, Some(call))
        @Expect(wrong, None<MacroCallId>)
        @Expect(expandedMacro(db, found.getOrThrow()).map {one => one.range.start}, Some(13 + offsetIn(
            file.text(db).toString()[13..], "@M")))
    }
}

/**
 * Hover and go to definition in the text of an expansion.
 */
@Test
class InExpansionTest {
    @TestCase
    func aNameTheMacroCopiedGoesToTheSource() {
        // arrange
        let (db, file, call, text) = answeredM()
        let source = file.text(db).toString()

        // act
        let targets = definitionInExpansion(db, call, offsetIn(text, "C", n: 1))

        // assert
        let c = offsetIn(source, "C {}")
        @Expect(targets.map {one => placeOf(one)}, ["${file.fileId(db)} ${TextRange(c, c + 1)}"])
    }

    @TestCase
    func aNameTheMacroWroteGoesToTheExpansion() {
        // arrange
        let (db, file, call, text) = answeredM()

        // act
        let targets = definitionInExpansion(db, call, offsetIn(text, "Gen", n: 1))

        // assert
        let gen = offsetIn(text, "Gen")
        @Expect(targets.map {one => placeOf(one)}, ["${file.fileId(db)} ${TextRange(gen, gen + 3)} in expansion"])
        @Expect(targets.map {one => one.expansion == Some(call)}, [true])
        @Expect(targets.map {one => text[one.fullRange.start..one.fullRange.end]}, ["class Gen {}"])
    }

    @TestCase
    func aTypeParameterTheMacroWroteGoesToTheExpansion() {
        // arrange
        let (db, file, call, text) = answeredM()

        // act
        let targets = definitionInExpansion(db, call, offsetIn(text, "t: T", plus: 3))

        // assert
        let t = offsetIn(text, "<T>", plus: 1)
        @Expect(targets.map {one => placeOf(one)}, ["${file.fileId(db)} ${TextRange(t, t + 1)} in expansion"])
    }

    @TestCase
    func aNameInABodyOfAnExpansionIsNotResolved() {
        // arrange
        let (db, _, call, text) = answeredM()

        // act
        let targets = definitionInExpansion(db, call, offsetIn(text, "C()"))
        let hover = hoverInExpansion(db, call, offsetIn(text, "C()"))

        // assert
        @Expect(targets.size, 0)
        @Expect(hover.isNone())
    }

    @TestCase
    func aNameOfAnExpansionIsHoveredAsInAFile() {
        // arrange
        let (db, _, call, text) = answeredM()

        // act
        let onType = hoverInExpansion(db, call, offsetIn(text, "Gen", n: 1))
        let onDecl = hoverInExpansion(db, call, offsetIn(text, "make"))

        // assert
        let gen = offsetIn(text, "Gen", n: 1)
        @Expect(onType?.range, Some(TextRange(gen, gen + 3)))
        @Expect(onType?.items.map {item => item.code}, Some(["class Gen"]))
        @Expect(onDecl?.items.map {item => item.code}, Some(["func make<T>(g: Gen, t: T): C"]))
    }

    @TestCase
    func inAStdDeriveATypeOfTheSourceGoesThereAndAMemberItDeclaresIsHovered() {
        // arrange
        let parsed = Fixture.parse(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Hashable]
            struct S {}
            "#)
        let db = deriveDatabase(parsed)
        let file = parsed.file("/main.cj")
        let call = macroCallAt(db, file.fileId, offsetIn(file.text, "Derive")).getOrThrow().call
        let text = expandedMacro(db, call).getOrThrow().text

        // act
        let onS = definitionInExpansion(db, call, offsetIn(text, "S <:"))
        let hover = hoverInExpansion(db, call, offsetIn(text, "hashCode"))

        // assert
        let s = offsetIn(file.text, "S {}")
        @Expect(onS.map {one => placeOf(one)}, ["${file.fileId} ${TextRange(s, s + 1)}"])
        @Expect(hover?.items.map {item => item.code}, Some(["public func hashCode(): Int64"]))
    }
}
