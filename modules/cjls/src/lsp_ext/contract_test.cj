package cjls.lsp_ext

import std.fs.*
import std.convert.Formattable
import std.sort.sort
import std.unittest.*
import std.unittest.testmacro.*

let SOURCES = Path("modules/cjls/src/lsp_ext")
let DOC = Path("docs/lsp-extensions.md")
let MARKER = "<!-- cjls.lsp_ext hash: "

/**
 * `docs/lsp-extensions.md` is what the editor clients read of this package (D32), so it names the
 * sources it describes by their hash, as R1's does `lsp/ext.rs`: a change here fails until the doc
 * has been read again and its hash moved.
 */
@Test
class LspExtensionsDocTest {
    @TestCase
    func theDocNamesTheHashOfTheExtensionsItDescribes(): Unit {
        // arrange
        let doc = String.fromUtf8(File.readFrom(DOC))

        // act
        let actual = sourcesHash()

        // assert: a new hash is written into the doc's first line once the doc says what changed
        @Expect(recordedHash(doc), actual)
    }
}

/** The hash on the doc's first line, `<!-- cjls.lsp_ext hash: … -->`, or "" without one. */
func recordedHash(doc: String): String {
    let line = doc.lines().next() ?? ""
    if (line.startsWith(MARKER) && line.endsWith(" -->")) {
        line[MARKER.size..line.size - 4]
    } else {
        ""
    }
}

/** FNV-1a over the package's sources, sorted by name, without their tests; `\r` left out, as a Windows checkout adds it. */
@OverflowWrapping
func sourcesHash(): String {
    let names = Directory.readFrom(SOURCES)
        .map {info => info.name}
        .filter {name => name.endsWith(".cj") && !name.endsWith("_test.cj")}
    sort(names)
    var hash: UInt64 = 0xcbf29ce484222325
    for (name in names) {
        for (byte in name.toArray()) {
            hash = (hash ^ UInt64(byte)) * 0x100000001b3
        }
        for (byte in File.readFrom(SOURCES.join(name)) where byte != b'\r') {
            hash = (hash ^ UInt64(byte)) * 0x100000001b3
        }
    }
    hash.format("016x")
}
