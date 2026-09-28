package ftoml

import std.unittest.*
import std.unittest.testmacro.*

/*
 * A document read and written back: one the size of a `cjpm.toml`, and one of about 1 MB of every kind of value, tables spread over the file
 * included.
 *
 * `cjpm bench '--filter=FtomlBench*'`
 */

let MANIFEST: Array<Byte> = #"
[package]
cjc-version = "1.3.0"
name = "demo"
description = "A demo for Cangjie"
version = "0.1.0"
target-dir = ""
src-dir = ""
output-type = "executable"
compile-option = "-Woff unused -O2 --static-std"
override-compile-option = ""
link-option = "-lc++"
package-configuration = { "demo" = { compile-option = "--static" } }

[dependencies]
core = { path = "../core" }
net = { path = "../net" }
json = { path = "../json" }
text = { path = "../text" }
log = { path = "../log" }

[test-dependencies]
fixtures = { path = "../fixtures" }

# stdx is the static one, unpacked per platform as the nightly zips lay it out
[target.aarch64-apple-darwin.bin-dependencies]
path-option = ["${CANGJIE_STDX_PATH}"]

[target.x86_64-unknown-linux-gnu.bin-dependencies]
path-option = ["${CANGJIE_STDX_PATH}"]

[target.x86_64-w64-mingw32.bin-dependencies]
path-option = ["${CANGJIE_STDX_PATH}"]

[profile.test]
no-color = false
timeout-each = "4m"
parallel = 8
"#.toArray()

let LARGE: Array<Byte> = {
    =>
    let sb = StringBuilder()
    var i = 0
    while (sb.size < 1024 * 1024) {
        sb.append("[[server]]\nname = \"server-${i}\"\nhost = \"10.0.${i % 256}.${i / 256 % 256}\"\n")
        sb.append("ports = [ 8000, 8001, 8002 ]\nweight = ${i}.25\nenabled = ${i % 2 == 0}\n")
        sb.append("started = 1979-05-27T07:32:00.${i % 1000}Z\nlabels = { zone = \"eu-${i % 3}\", tier = 'gold' }\n")
        sb.append("description = \"\"\"\nA server named \\\"${i}\\\", with a note\tthat spans\nlines.\"\"\"\n\n")
        sb.append("[server.limits]\ncpu = 0x2A\nmemory = 1_024\n\n")
        i++
    }
    sb.toString().toArray()
}()

let MANIFEST_DOCUMENT: FtDocument = parseToml(MANIFEST)

let LARGE_DOCUMENT: FtDocument = parseToml(LARGE)

var benchSink = 0

@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class FtomlBench {
    @Bench
    func readManifest(): Unit {
        benchSink += parseToml(MANIFEST).table.size
    }

    @Bench
    func writeManifest(): Unit {
        benchSink += toTomlBytes(MANIFEST_DOCUMENT.root).size
    }

    @Bench
    func readLarge(): Unit {
        benchSink += parseToml(LARGE).table.size
    }

    @Bench
    func writeLarge(): Unit {
        benchSink += toTomlBytes(LARGE_DOCUMENT.root).size
    }
}
