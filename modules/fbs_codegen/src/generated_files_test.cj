package fbs_codegen

import std.collection.*
import std.env.getTempDirectory
import std.fs.*
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
    func invalidGeneratedSourceDoesNotOverwriteAFile(): Unit {
        let dir = Directory.createTemp(getTempDirectory())
        try {
            let path = dir.join("output.cj")
            File.writeTo(path, "keep".toArray())
            @AssertThrows[IllegalStateException](writeFormatted(path, "func broken( {"))
            @Expect(String.fromUtf8(File.readFrom(path)), "keep")
            writeFormatted(path, "func f() {call(a,\nb)}")
            @Expect(String.fromUtf8(File.readFrom(path)), "func f() {\n    call(a, b)\n}\n")
        } finally {
            remove(dir, recursive: true)
        }
    }

    @TestCase
    func theCheckedInFilesAreWhatTheGeneratorMakes() {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        let stale = ArrayList<String>()

        // act
        try {
            for (config in CONFIGS) {
                let file = generate(Path(config))
                let fresh = dir.join(file.path.fileName)
                writeFormatted(fresh, file.contents)
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
