package cjformat.config

import std.env.getTempDirectory
import std.fs.{Directory, File}
import cjformat.formatText

@Test
class FormatConfigTest {
    @TestCase
    func nearestConfigReplacesTheParentAndMissingKeysUseDefaults(): Unit {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        Directory.create(dir.join("nested"))
        File.writeTo(dir.join("cjformat.toml"), "line_width = 40\nindent_width = 2\n".toArray())
        File.writeTo(dir.join("nested/cjformat.toml"), "simple_if = 'compact'\n".toArray())

        // act
        let parent = optionsFor(dir.join("a.cj"))
        let child = optionsFor(dir.join("nested/a.cj"))

        // assert
        @Expect(parent.lineWidth, 40)
        @Expect(parent.indentWidth, 2)
        @Expect(child.lineWidth, 100)
        @Expect(child.indentWidth, 4)
        @Expect(formatText("let x = if (a) { b } else { c }", options: child),
            Some("let x = if (a) { b } else { c }\n"))
    }

    @TestCase
    func invalidSettingsAreRejectedRatherThanSilentlyIgnored(): Unit {
        // arrange
        let invalid =
            [
                "line_width = 0",
                "indent_width = -1",
                "simple_if = 'flat'",
                "line_width = '80'",
                "indent_width = true",
                "unknown = 1",
                "[layout]\nwidth = 80",
                "line_width = 80\nline_width = 90",
                "line_width = ["
            ]

        // act / assert
        for (source in invalid) {
            @AssertThrows[Exception](parseOptions(source))
        }
    }
}
