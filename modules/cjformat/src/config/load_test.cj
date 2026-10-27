package cjformat.config

import std.env.getTempDirectory
import std.fs.{Directory, File, remove}
import cjformat.{SimpleIf, formatText}
import ftoml.FtException

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
        for (source in invalid[..2]) {
            @AssertThrows[IllegalArgumentException](parseOptions(source))
        }
        for (source in invalid[2..]) {
            @AssertThrows[FtException](parseOptions(source))
        }
    }

    @TestCase
    func emptyAndPartialConfigsUseLibraryDefaults(): Unit {
        // act
        let defaults = parseOptions("")
        let custom = parseOptions("line_width = 72\nsimple_if = 'compact'")

        // assert
        @Expect(defaults.lineWidth, 100)
        @Expect(defaults.indentWidth, 4)
        @Expect(match (defaults.simpleIf) { case SimpleIf.Multiline => true; case _ => false })
        @Expect(custom.lineWidth, 72)
        @Expect(custom.indentWidth, 4)
        @Expect(match (custom.simpleIf) { case SimpleIf.Compact => true; case _ => false })
    }

    @TestCase
    func configFailuresNameThePathAndUseTheDomainException(): Unit {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        let path = dir.join("cjformat.toml")
        File.writeTo(path, "unknown = 1".toArray())

        // act
        let error = @AssertThrows[FormatConfigException](optionsFor(dir.join("a.cj")))

        // assert
        @Expect(error.message.contains(path.toString()))
        @Expect(error.message.contains("unknown"))
        @Expect(error.getClassName(), "FormatConfigException")
    }

    @TestCase
    func unreadableAndInvalidUtf8ConfigsUseTheDomainException(): Unit {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        let path = dir.join("cjformat.toml")
        Directory.create(path)

        // act / assert
        @AssertThrows[FormatConfigException](optionsFor(dir.join("a.cj")))

        // arrange
        remove(path)
        File.writeTo(path, [0xFFu8])

        // act / assert
        @AssertThrows[FormatConfigException](optionsFor(dir.join("a.cj")))
    }
}
