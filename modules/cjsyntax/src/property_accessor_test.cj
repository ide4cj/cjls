package cjsyntax

import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange

@Test
class PropertyAccessorParseTest {
    @TestCase
    func unknownNamesKeepTheBodyAndFollowingDeclarations(): Unit {
        // arrange
        let source = "class C { prop x: Int64 { foo() { 1 } } func after() {} }"

        // act
        let parsed = parse(source)

        // assert
        @Expect(parsed.syntaxNode().text(), source)
        @Expect(parsed.errors.size, 1)
        @Expect(message(parsed.errors[0].error), "expected 'get' or 'set' in prop body, found 'foo'")
        @Expect(parsed.errors[0].range, TextRange(26, 29))

        // act
        let corrected = reparse(parsed, TextRange(26, 29), "get")

        // assert
        @Expect(corrected.errors.isEmpty())
    }
    @TestCase
    func nestedPropertyNamesAgreeAfterIncrementalEdits(): Unit {
        // arrange
        let source = "func f() { class C { prop x: Int64 { get() { 1 } } } }"
        let start = source.indexOf("get").getOrThrow()
        let range = TextRange(start, start + 3)
        let before = parse(source)
        let broken = source[..start] + "foo" + source[start + 3..]

        // act
        let edited = reparse(before, range, "foo")
        let fresh = parse(broken)

        // assert
        @Expect(edited, fresh)
        @Expect(edited.errors.size, before.errors.size + 1)
        @Expect(edited.errors.any { error => message(error.error) == "expected 'get' or 'set' in prop body, found 'foo'" })

        // act
        let corrected = reparse(edited, range, "get")

        // assert
        @Expect(corrected, before)
    }
    @TestCase
    func structPropertiesNeedBodies(): Unit {
        // arrange
        let source = "struct S { prop x: Int64 }"

        // act
        let parsed = parse(source)

        // assert
        @Expect(parsed.errors.size, 1)
        @Expect(message(parsed.errors[0].error), "expected '{': a property needs a body here")
    }
}
