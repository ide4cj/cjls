package macro_host

import std.collection.*
import std.env.getTempDirectory
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import platform.sharedLibrarySuffix

/**
 * A `cjc` that writes what a build of a package writes last, or fails on the packages named.
 */
class FakeToolchain <: Toolchain {
    let calls = ArrayList<Array<String>>()

    FakeToolchain(let failing!: Array<String> = []) {}

    public func compile(arguments: Array<String>): (Int64, String) {
        calls.add(arguments)
        let dir =
            arguments.iterator().filter { a => a.startsWith("--output-dir=") }.next().getOrThrow()
        let out = Path(dir["--output-dir=".size..])
        let name = Path(arguments[1]).fileName
        if (failing.contains(name)) {
            return (1, "error: ${name} does not compile")
        }
        let file =
            if (arguments.contains("--compile-macro")) {
                "lib-macro_m.${name}${sharedLibrarySuffix()}"
            } else {
                "libm.${name}.a"
            }
        File.writeTo(out.join(file), [])
        (0, "")
    }

    func names(): Array<String> {
        calls.toArray().map { call => Path(call[1]).fileName }
    }
}

/**
 * A fresh directory of sources `m.<name>` for each of `names`, and the directory a build goes to.
 */
func sources(names: Array<String>): (Path, Path) {
    let root = Directory.createTemp(getTempDirectory())
    for (name in names) {
        Directory.create(root.join("src").join(name), recursive: true)
        File
            .writeTo(
                root.join("src").join(name).join("${name}.cj"),
                "package m.${name}\n".toArray()
            )
    }
    (root.join("src"), root.join("macro-build"))
}

func unit(src: Path, name: String, isMacro!: Bool = false, deps!: Array<String> = []): BuildUnit {
    BuildUnit("m.${name}", "m", src.join(name), isMacro, deps.map { dep => ("m", "m.${dep}") }, [])
}

@Test
class MacroBuilderTest {
    @TestCase
    func aMacroPackageIsBuiltAfterWhatItImportsWithCjpmsArguments() {
        // arrange
        let (src, out) = sources(["util", "ms"])
        let toolchain = FakeToolchain()
        let builder = MacroBuilder(out, "cjc 1", toolchain)

        // act
        let built =
            builder
                .build([unit(src, "util"), unit(src, "ms", isMacro: true, deps: ["util"])])
                .getOrThrow()

        // assert
        @Expect(toolchain.names(), ["util", "ms"])
        @Expect(toolchain.calls[0], ["-p", src.join("util").toString(), "--import-path=${out}", "--no-sub-pkg",
            "--output-dir=${out.join("m")}", "--output-type=staticlib", "-o=libm.util.a"])
        @Expect(toolchain.calls[1], ["-p", src.join("ms").toString(), "--import-path=${out}", "--no-sub-pkg",
            "--output-dir=${out.join("m")}", "-L", out.join("m").toString(), "-lm.util", "--compile-macro"])
        @Expect(built.size, 1)
        match (built.get("m.ms")) {
            case Some(Built(library, _)) =>
                @Expect(library, out.join("m").join("lib-macro_m.ms${sharedLibrarySuffix()}"))
            case _ => @Fail("m.ms was not built")
        }
    }

    @TestCase
    func whatDidNotChangeIsNotBuiltAgain() {
        // arrange
        let (src, out) = sources(["util", "ms"])
        let units = [unit(src, "util"), unit(src, "ms", isMacro: true, deps: ["util"])]
        let first = MacroBuilder(out, "cjc 1", FakeToolchain()).build(units).getOrThrow()
        let toolchain = FakeToolchain()

        // act
        let second = MacroBuilder(out, "cjc 1", toolchain).build(units).getOrThrow()

        // assert
        @Expect(toolchain.names().size, 0)
        @Expect(stampOf(second, "m.ms"), stampOf(first, "m.ms"))
    }

    @TestCase
    func anEditToWhatAMacroPackageImportsBuildsBothAgainUnderANewStamp() {
        // arrange
        let (src, out) = sources(["util", "ms"])
        let units = [unit(src, "util"), unit(src, "ms", isMacro: true, deps: ["util"])]
        let first = MacroBuilder(out, "cjc 1", FakeToolchain()).build(units).getOrThrow()
        File.writeTo(src.join("util").join("util.cj"), "package m.util\nfunc f() {}\n".toArray())
        let toolchain = FakeToolchain()

        // act
        let second = MacroBuilder(out, "cjc 1", toolchain).build(units).getOrThrow()

        // assert
        @Expect(toolchain.names(), ["util", "ms"])
        @Expect(stampOf(second, "m.ms") != stampOf(first, "m.ms"))
    }

    @TestCase
    func anotherCompilerBuildsEverythingAgain() {
        // arrange
        let (src, out) = sources(["ms"])
        let units = [unit(src, "ms", isMacro: true)]
        MacroBuilder(out, "cjc 1", FakeToolchain()).build(units).getOrThrow()
        let toolchain = FakeToolchain()

        // act
        MacroBuilder(out, "cjc 2", toolchain).build(units).getOrThrow()

        // assert
        @Expect(toolchain.names(), ["ms"])
    }

    @TestCase
    func aMacroPackageWhoseImportFailsIsNotBuiltAndSaysWhy() {
        // arrange
        let (src, out) = sources(["util", "ms"])
        let toolchain = FakeToolchain(failing: ["util"])

        // act
        let built =
            MacroBuilder(out, "cjc 1", toolchain)
                .build([unit(src, "util"), unit(src, "ms", isMacro: true, deps: ["util"])])
                .getOrThrow()

        // assert
        @Expect(toolchain.names(), ["util"])
        match (built.get("m.ms")) {
            case Some(NotBuilt(reason)) =>
                @Expect(reason, "m.util, which it imports, did not build")
            case _ => @Fail("m.ms was built")
        }
    }

    @TestCase
    func nothingIsBuiltWhileAnotherHoldsTheLock() {
        // arrange
        let (src, out) = sources(["ms"])
        let toolchain = FakeToolchain()
        let held = tryLockCacheDir(out).getOrThrow()

        // act
        let built =
            try {
                MacroBuilder(out, "cjc 1", toolchain).build([unit(src, "ms", isMacro: true)])
            } finally {
                held.close()
            }

        // assert
        @Expect(built.isNone())
        @Expect(toolchain.names().size, 0)
    }

    @TestCase
    func aBuildLeavesTheLockFree() {
        // arrange
        let (src, out) = sources(["ms"])
        MacroBuilder(out, "cjc 1", FakeToolchain()).build([unit(src, "ms", isMacro: true)])

        // act
        let lock = tryLockCacheDir(out)

        // assert
        @Expect(lock.isSome())
        lock?.close()
    }
}

func stampOf(built: HashMap<String, BuiltLibrary>, name: String): Int64 {
    match (built.get(name)) {
        case Some(Built(_, stamp)) => stamp
        case _ => -1
    }
}
