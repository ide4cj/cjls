package lsp_codegen

import std.fs.{File, Path}
import std.unittest.*
import std.unittest.testmacro.*
import cjformat.formatText
import cjformat.config.optionsFor
import fjson.fromJsonBytes

/**
 * Generation must produce canonical source without a formatter subprocess.
 */
@Test
class GeneratedFilesTest {
    @TestCase
    func theCheckedInFilesAreWhatTheGeneratorMakes(): Unit {
        // arrange
        let config = Config.load(Path("modules/cjls/lsp_codegen.toml"))
        let model = fromJsonBytes<MetaModel>(File.readFrom("modules/lsp_codegen/metaModel.json"))

        // act
        let files = generateCjFiles(config, model)

        // assert
        @Expect(!files.isEmpty())
        for (file in files) {
            @Expect(formatText(file.contents, options: optionsFor(file.path)), Some(file.contents))
            @Expect(String.fromUtf8(File.readFrom(file.path)), file.contents)
        }
    }
}
