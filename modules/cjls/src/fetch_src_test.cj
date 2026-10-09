package cjls

import std.collection.{ArrayList, HashMap}
import std.env.getTempDirectory
import std.fs.{Directory, File, Path, exists}
import std.io.ByteBuffer

const NOTES = """
{"tag_name":"1.3.0-alpha.20261002001050","body":"## Cangjie Nightly Build Version: **1.3.0-alpha.20261002001050**\\n\\n## Commit IDs / 构建提交ID\\n\\n- **cangjie_compiler**: `514a5a209e42`\\n- **cangjie_runtime**: `5d555bcc34d6`\\n- **cangjie_tools**: `3009d063056e`\\n"}
"""

const VERSION_OUTPUT = "Cangjie Compiler: 1.3.0-alpha.20261002001050 (cjnative)\nTarget: x86_64-unknown-linux-gnu\n"

/**
 * The network, `tar` and `cjc` of a test: `pages` by URL, an archive that unpacks into `tree`
 * (`cangjie_runtime-<commit>/…` relative paths and their text); what was asked for, in `asked`.
 */
class FakeSrcHost <: SrcHost {
    let asked = ArrayList<String>()

    FakeSrcHost(
        let version: ?String,
        let pages: HashMap<String, String>,
        let tree: Array<(String, String)>
    ) {}

    public func compilerVersion(cjc: Path): ?String {
        asked.add("cjc ${cjc.fileName}")
        version
    }

    public func get(url: String): ?String {
        asked.add("get ${url}")
        pages.get(url)
    }

    public func download(url: String, to: Path): Bool {
        asked.add("download ${url}")
        File.writeTo(to, "archive".toArray())
        true
    }

    public func unpack(archive: Path, into: Path): Bool {
        asked.add("unpack")
        for ((path, text) in tree) {
            let file = path.split("/").fold(into) {dir, name => dir.join(name)}
            Directory.create(file.parent, recursive: true)
            File.writeTo(file, text.toArray())
        }
        true
    }
}

let GITHUB_NOTES = "https://api.github.com/repos/cangjie-bot/nightly_build/releases/tags/1.3.0-alpha.20261002001050"
let GITCODE_NOTES = "https://api.gitcode.com/api/v5/repos/Cangjie/nightly_build/releases/tags/1.3.0-alpha.20261002001050"

let RUNTIME_TREE = [
    ("cangjie_runtime-5d555bcc34d6/LICENSE", "license"),
    ("cangjie_runtime-5d555bcc34d6/stdlib/libs/CMakeLists.txt", ""),
    ("cangjie_runtime-5d555bcc34d6/stdlib/libs/std/core/string.cj", "package std.core\n"),
    ("cangjie_runtime-5d555bcc34d6/runtime/src/gc.cpp", "")
]

func sdkHome(): Path {
    let home = Directory.createTemp(getTempDirectory())
    Directory.create(home.join("bin"))
    home
}

@Test
class FetchSrcTest {
    @TestCase
    func theVersionIsWhatCjcPrints() {
        // act, assert
        @Expect(compilerVersionOf(VERSION_OUTPUT), Some("1.3.0-alpha.20261002001050"))
        @Expect(compilerVersionOf("Cangjie Compiler: 1.0.0 (cjnative)\r\n"), Some("1.0.0"))
        @Expect(compilerVersionOf("cjc: command not found\n"), Option<String>.None)
    }

    @TestCase
    func theCommitIsTheOneTheReleaseNotesNameForCangjieRuntime() {
        // act, assert
        @Expect(runtimeCommitOf(NOTES), Some("5d555bcc34d6"))
        @Expect(runtimeCommitOf("- **cangjie_runtime**: `not-a-commit`"), Option<String>.None)
        @Expect(runtimeCommitOf("- **cangjie_runtime**: 5d555bcc34d6"), Option<String>.None)
        @Expect(runtimeCommitOf("{\"message\":\"Not Found\"}"), Option<String>.None)
    }

    @TestCase
    func stdAndItsLicenseGoToTheDirStampedWithTheCommit() {
        // arrange
        let home = sdkHome()
        let dir = home.join("src")
        let host = FakeSrcHost(VERSION_OUTPUT, HashMap([(GITHUB_NOTES, NOTES)]), RUNTIME_TREE)
        let (out, err) = (ByteBuffer(), ByteBuffer())

        // act
        let exitCode = fetchSrc(home, dir, host, out, err)

        // assert
        @Expect(exitCode, 0)
        @Expect(String.fromUtf8(File.readFrom(dir.join("std").join("core").join("string.cj"))), "package std.core\n")
        @Expect(exists(dir.join("LICENSE")))
        @Expect(!exists(dir.join("CMakeLists.txt")))
        @Expect(!exists(dir.join("runtime")))
        @Expect(stampOf(dir), Some("5d555bcc34d6"))
        @Expect(!exists(Path("${dir}.part")))
        @Expect(written(out), "${dir}\n")
        @Expect(host.asked.toArray(), [
            "cjc ${CJC}",
            "get ${GITHUB_NOTES}",
            "download https://github.com/cangjie-bot/cangjie_runtime/archive/5d555bcc34d6.tar.gz",
            "unpack"
        ])
    }

    @TestCase
    func theNotesOfGitcodeAreReadWhenTheMirrorHasNone() {
        // arrange
        let home = sdkHome()
        let host = FakeSrcHost(VERSION_OUTPUT, HashMap([(GITCODE_NOTES, NOTES)]), RUNTIME_TREE)

        // act
        let exitCode = fetchSrc(home, home.join("src"), host, ByteBuffer(), ByteBuffer())

        // assert
        @Expect(exitCode, 0)
        @Expect(host.asked[1..3].toArray(), ["get ${GITHUB_NOTES}", "get ${GITCODE_NOTES}"])
        @Expect(stampOf(home.join("src")), Some("5d555bcc34d6"))
    }

    @TestCase
    func sourcesOfTheCommitAlreadyThereAreNotDownloadedAgain() {
        // arrange
        let home = sdkHome()
        let dir = home.join("src")
        fetchSrc(home, dir, FakeSrcHost(VERSION_OUTPUT, HashMap([(GITHUB_NOTES, NOTES)]), RUNTIME_TREE),
            ByteBuffer(), ByteBuffer())
        let host = FakeSrcHost(VERSION_OUTPUT, HashMap([(GITHUB_NOTES, NOTES)]), RUNTIME_TREE)

        // act
        let exitCode = fetchSrc(home, dir, host, ByteBuffer(), ByteBuffer())

        // assert
        @Expect(exitCode, 0)
        @Expect(host.asked.toArray().filter {it => it.startsWith("download")}.size, 0)
    }

    @TestCase
    func sourcesOfAnotherCommitAreReplaced() {
        // arrange
        let home = sdkHome()
        let dir = home.join("src")
        Directory.create(dir.join("std").join("old"), recursive: true)
        File.writeTo(dir.join(SRC_STAMP), "0123456789ab\n".toArray())
        let host = FakeSrcHost(VERSION_OUTPUT, HashMap([(GITHUB_NOTES, NOTES)]), RUNTIME_TREE)

        // act
        let exitCode = fetchSrc(home, dir, host, ByteBuffer(), ByteBuffer())

        // assert
        @Expect(exitCode, 0)
        @Expect(!exists(dir.join("std").join("old")))
        @Expect(stampOf(dir), Some("5d555bcc34d6"))
    }

    @TestCase
    func aDirOfTheUsersIsLeftAlone() {
        // arrange
        let home = sdkHome()
        let dir = home.join("src")
        Directory.create(dir)
        File.writeTo(dir.join("mine.txt"), "mine".toArray())
        let host = FakeSrcHost(VERSION_OUTPUT, HashMap([(GITHUB_NOTES, NOTES)]), RUNTIME_TREE)
        let err = ByteBuffer()

        // act
        let exitCode = fetchSrc(home, dir, host, ByteBuffer(), err)

        // assert
        @Expect(exitCode, 1)
        @Expect(exists(dir.join("mine.txt")))
        @Expect(!exists(dir.join("std")))
        @Expect(written(err).contains("not replaced"))
    }

    @TestCase
    func aVersionNoReleaseNotesNameIsAFailureSayingSo() {
        // arrange
        let home = sdkHome()
        let host = FakeSrcHost("Cangjie Compiler: 1.0.0 (cjnative)\n", HashMap(), RUNTIME_TREE)
        let (out, err) = (ByteBuffer(), ByteBuffer())

        // act
        let exitCode = fetchSrc(home, home.join("src"), host, out, err)

        // assert
        @Expect(exitCode, 1)
        @Expect(written(out), "")
        @Expect(written(err).contains("a release SDK's sources are not fetched"))
        @Expect(!exists(home.join("src")))
    }

    @TestCase
    func anSdkWhoseCjcDoesNotRunIsAFailure() {
        // arrange
        let home = sdkHome()
        let host = FakeSrcHost(None, HashMap(), RUNTIME_TREE)

        // act
        let exitCode = fetchSrc(home, home.join("src"), host, ByteBuffer(), ByteBuffer())

        // assert
        @Expect(exitCode, 1)
        @Expect(host.asked.size, 1)
    }

    @TestCase
    func anArchiveWithoutStdIsAFailureLeavingNothing() {
        // arrange
        let home = sdkHome()
        let host = FakeSrcHost(VERSION_OUTPUT, HashMap([(GITHUB_NOTES, NOTES)]),
            [("cangjie_runtime-5d555bcc34d6/README.md", "")])

        // act
        let exitCode = fetchSrc(home, home.join("src"), host, ByteBuffer(), ByteBuffer())

        // assert
        @Expect(exitCode, 1)
        @Expect(!exists(home.join("src")))
        @Expect(!exists(home.join("src.part")))
    }
}
