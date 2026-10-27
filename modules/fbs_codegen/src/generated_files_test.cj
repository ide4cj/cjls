package fbs_codegen

import std.collection.ArrayList
import std.env.getTempDirectory
import cjformat.config.optionsFor
import std.fs.{Directory, File, Path, remove}
import std.unittest.*
import std.unittest.testmacro.*

let CONFIGS = ["modules/cjo/cjo_format.toml", "modules/macro_server/macro_msg_format.toml"]

/**
 * A change to a schema, its config or the generator that was not generated fails here, and with it
 * `pre-push`.
 */
@Test
class GeneratedFilesTest {
    @TestCase
    func generatedOutputUsesItsProjectSettings(): Unit {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        let path = dir.join("output.cj")
        File
            .writeTo(
                dir.join("cjformat.toml"),
                "indent_width = 2\nsimple_if = 'compact'\n".toArray()
            )

        // act
        try {
            writeFormatted(path, "func f() { if (a) { b } else { c } }")

            // assert
            @Expect(String.fromUtf8(File.readFrom(path)),
                "func f() {\n  if (a) { b } else { c }\n}\n")
        } finally {
            remove(dir, recursive: true)
        }
    }

    @TestCase
    func invalidGeneratedSourceDoesNotOverwriteAFile(): Unit {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        try {
            let path = dir.join("output.cj")
            File.writeTo(path, "keep".toArray())

            // act
            @AssertThrows[IllegalStateException](writeFormatted(path, "func broken( {"))
            let preserved = String.fromUtf8(File.readFrom(path))

            // assert
            @Expect(preserved, "keep")

            // act
            writeFormatted(path, "func f() {call(a,\nb)}")
            let formatted = String.fromUtf8(File.readFrom(path))

            // assert
            @Expect(formatted, "func f() {\n    call(a, b)\n}\n")
        } finally {
            remove(dir, recursive: true)
        }
    }

    @TestCase
    func theCheckedInFilesAreWhatTheGeneratorMakes(): Unit {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        let stale = ArrayList<String>()

        // act
        try {
            for (config in CONFIGS) {
                let file = generate(Path(config))
                let fresh = dir.join(file.path.fileName)
                writeFormatted(fresh, file.contents, options: optionsFor(file.path))
                if (File.readFrom(fresh) != File.readFrom(file.path)) {
                    stale
                        .add(
                            "${file.path} is out of date: `cjpm build`, then `target/release/bin/fbs_codegen ${config}`"
                        )
                }
            }
        } finally {
            remove(dir, recursive: true)
        }

        // assert
        @Expect(stale.toArray(), Array<String>())
    }
}
