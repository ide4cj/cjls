package lsp_codegen

import std.fs.{File, Path}
import std.unittest.*
import std.unittest.testmacro.*
import cjformat.formatText
import fjson.fromJsonBytes

/** Generation must produce canonical source without a formatter subprocess. */
@Test
class GeneratedFilesTest {
    @TestCase
    func theCheckedInFilesAreWhatTheGeneratorMakes(): Unit {
        let config = Config.load(Path("modules/cjls/lsp_codegen.toml"))
        let model = fromJsonBytes<MetaModel>(File.readFrom("modules/lsp_codegen/metaModel.json"))
        let files = generateCjFiles(config, model)
        @Expect(!files.isEmpty())
        for (file in files) {
            @Expect(formatText(file.contents), Some(file.contents))
            @Expect(String.fromUtf8(File.readFrom(file.path)), file.contents)
        }
    }
}
