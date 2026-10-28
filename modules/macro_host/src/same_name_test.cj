package macro_host

import std.collection.*
import std.env.getTempDirectory
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import macro_server.*

/** A different direct package name must not hide the conflicting linked helper package. */
func conflictingLibraries(
    root: Path,
    toolchain: SdkToolchain,
    sameName: Bool
): Array<(String, String)> {
    let found = ArrayList<(String, String)>()
    for (name in ["First", "Second"]) {
        let source = root.join(name).join("src")
        let leaf = root.join(name).join("leaf")
        Directory.create(source, recursive: true)
        Directory.create(leaf, recursive: true)
        let value = if (name == "First") { "1" } else { "2" }
        let pkg = if (sameName) { "toy.ms" } else { "toy.${name}" }
        File
            .writeTo(
                leaf.join("leaf.cj"),
                "package leaf\npublic func which(): Int64 { ${value} }\n".toArray()
            )
        let text =
            "macro package ${pkg}\nimport std.ast.*\nimport leaf.*\npublic macro Which(input: Tokens): Tokens { if (which() == 1) { quote(class First {}) } else { quote(class Second {}) } }\n"
        File.writeTo(source.join("ms.cj"), text.toArray())
        let built =
            MacroBuilder(
                root.join(name).join("macro-build"),
                toolchain.version().getOrThrow(),
                toolchain
            )
                .build(
                    [
                        BuildUnit("leaf", "leaf", leaf, false, [], []),
                        BuildUnit(pkg, "toy", source, true, [("leaf", "leaf")], [])
                    ]
                )
                .getOrThrow()
        match (built.get(pkg).getOrThrow()) {
            case Built(path, _) => found.add((path.toString(), pkg))
            case NotBuilt(reason) => throw IllegalStateException(reason)
        }
    }
    found.toArray()
}

func conflictingLibraryCall(library: String, pkg: String, numbers: TokenNumbers): MacroCallData {
    MacroCallData(
        id: IdInfoData(name: "Which", pos: PositionData(fileId: 1, line: 1, column: 2)),
        args: macroTokens("class A {}", numbers, PositionData(fileId: 1, line: 2, column: 1)),
        methodName: methodNameOf("Which", pkg, false),
        packageName: pkg,
        libPath: library,
        begin: PositionData(fileId: 1, line: 1, column: 1),
        end: PositionData(fileId: 1, line: 2, column: 11)
    )
}

@Test
class SameNameMacroLibraryTest {
    @TestCase[sameName in [true, false]]
    func changingTheSelectedLibraryCannotReuseAnotherGraphsMacroCode(sameName: Bool) {
        // arrange
        let paths = testSdkPaths()
        let numbers = testNumbers()
        let root = Directory.createTemp(getTempDirectory())
        let server = MacroServers(paths, Duration.minute, NoopLogger())
        try {
            let libraries = conflictingLibraries(root, SdkToolchain(paths), sameName)

            // act
            let outputs = ArrayList<String>()
            for (index in [0, 1, 0, 1]) {
                let (library, pkg) = libraries[index]
                match (server.expand(conflictingLibraryCall(library, pkg, numbers))) {
                    case Answered(result) =>
                        if (result.status == MACRO_FAILED) {
                            throw IllegalStateException("macro expansion failed")
                        }
                        outputs.add(printMacroTokens(result.tks, numbers).text)
                    case Unanswered(reason) => throw IllegalStateException(reason)
                }
            }

            // assert
            @Expect(outputs.toArray(), ["class First { }", "class Second { }", "class First { }", "class Second { }"])
        } finally {
            server.close()
            remove(root, recursive: true)
        }
    }
}
