package cjformat

import cjsyntax.parse
import ginkgo.TextRange

@Test
class FormatOptionsTest {
    @TestCase
    func anElseIfChainDoesNotCompactOnlyItsFinalBranches(): Unit {
        // arrange
        let source = "let x = if (a) { b } else if (c) { d } else { e }\n"
        let options = FormatOptions(simpleIf: SimpleIf.Compact)

        // act
        let formatted = formatText(source, options: options).getOrThrow()

        // assert
        @Expect(formatted.contains("else if (c) {\n"))
        @Expect(formattingProblems("else-if", source, options: options), [])
    }

    @TestCase
    func nestedValueBranchesKeepTheirStructureAndCanonicalLayout(): Unit {
        // arrange
        var expression = "0"
        for (_ in 0..16) {
            expression = "if (a) { ${expression} } else { 0 }"
        }
        let source = "let x = ${expression}\n"
        let options = FormatOptions(lineWidth: 1000, simpleIf: SimpleIf.Compact)

        // act
        let formatted = formatText(source, options: options)

        // assert
        @Expect(formatted, Some(source))
        @Expect(formattingProblems("nested-if", source, options: options), [])
    }

    @TestCase
    func aSelectedStatementUsesTheConfiguredWidthAndStructuralIndent(): Unit {
        // arrange
        let source = "func f() {\ncall(firstArgument, secondArgument)\n}\n"
        let options = FormatOptions(lineWidth: 30, indentWidth: 2)
        let at = source.indexOf("call").getOrThrow()
        let expected = "func f() {\n  call(\n    firstArgument,\n    secondArgument\n  )\n}\n"

        // act
        let edits = formatRange(parse(source), TextRange(at, at + 4), options: options)

        // assert
        @Expect(applyEdits(source, edits.getOrThrow()), expected)
    }

    @TestCase
    func widthsAndIndentationApplyToTheWholeFileAndRanges(): Unit {
        // arrange
        let source = "func f() { call(firstArgument, secondArgument) }\n"
        let options = FormatOptions(lineWidth: 30, indentWidth: 2)
        let expected = "func f() {\n  call(\n    firstArgument,\n    secondArgument\n  )\n}\n"

        // act
        let formatted = formatText(source, options: options)
        let ranged = formatRange(parse(source), TextRange(0, source.size), options: options)

        // assert
        @Expect(formatted, Some(expected))
        @Expect(formattingProblems("options", source, options: options), [])
        @Expect(applyEdits(source, ranged.getOrThrow()), expected)
        @Expect(formatText(expected, options: options), Some(expected))
    }

    @TestCase
    func compactIfFitsAsAWholeAndMultilineRemainsAvailable(): Unit {
        // arrange
        let source = "let x = if (a) { b } else { c }\n"
        let compact = FormatOptions(simpleIf: SimpleIf.Compact)
        let narrow = FormatOptions(lineWidth: 20, simpleIf: SimpleIf.Compact)

        // act
        let flat = formatText(source, options: compact)
        let expanded = formatText(source)
        let wrapped = formatText(source, options: narrow)

        // assert
        @Expect(flat, Some(source))
        @Expect(formattingProblems("compact", source, options: compact), [])
        @Expect(expanded.getOrThrow().contains("{\n"))
        @Expect(wrapped.getOrThrow().contains("{\n"))
        @Expect(formatText(wrapped.getOrThrow(), options: narrow), wrapped)
    }

    @TestCase
    func commentsAndMultipleStatementsPreventCompactIf(): Unit {
        // arrange
        let options = FormatOptions(simpleIf: SimpleIf.Compact)
        let commented = "let x = if (a) { /* why */ b } else { c }\n"
        let statements = "func f() { if (a) { b\nc } else { d } }\n"

        // act
        let first = formatText(commented, options: options).getOrThrow()
        let second = formatText(statements, options: options).getOrThrow()

        // assert
        @Expect(first.contains("{\n"))
        @Expect(second.contains("{\n"))
        @Expect(formatText(first, options: options), Some(first))
        @Expect(formatText(second, options: options), Some(second))
    }
}
