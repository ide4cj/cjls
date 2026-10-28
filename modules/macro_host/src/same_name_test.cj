package macro_host

import std.collection.*
import std.env.getTempDirectory
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import macro_server.*

/** SDK fixtures for K28's direct-package and linked-helper conflicts. */
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
            "macro package ${pkg}\n" +
                #"
import std.ast.*
import std.env.getProcessId
import leaf.*
public macro Which(input: Tokens): Tokens {
    if (which() == 1) { quote(class First {}) } else { quote(class Second {}) }
}
public macro Host(input: Tokens): Tokens {
    let name = Token(IDENTIFIER, "P" + getProcessId().toString()).toTokens()
    quote(class $name {})
}
"#
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

func conflictingLibraryCall(
    library: String,
    pkg: String,
    numbers: TokenNumbers,
    name!: String = "Which"
): MacroCallData {
    MacroCallData(
        id: IdInfoData(name: name, pos: PositionData(fileId: 1, line: 1, column: 2)),
        args: macroTokens("class A {}", numbers, PositionData(fileId: 1, line: 2, column: 1)),
        methodName: methodNameOf(name, pkg, false),
        packageName: pkg,
        libPath: library,
        begin: PositionData(fileId: 1, line: 1, column: 1),
        end: PositionData(fileId: 1, line: 2, column: 11)
    )
}

@Test
class SameNameMacroLibraryTest {
    @TestCase[sameName in [true, false]]
    func explicitRestartLoadsEachSelectedLibrary(sameName: Bool) {
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
                server.restartWorkspace()
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

    @TestCase
    func changingLibrariesReusesTheWorkspaceProcess() {
        // arrange
        let paths = testSdkPaths()
        let numbers = testNumbers()
        let root = Directory.createTemp(getTempDirectory())
        let server = MacroServers(paths, Duration.minute, NoopLogger())
        try {
            let libraries = conflictingLibraries(root, SdkToolchain(paths), false)

            // act
            let hosts = ArrayList<String>()
            for (index in [0, 1, 0, 1]) {
                let (library, pkg) = libraries[index]
                match (server.expand(conflictingLibraryCall(library, pkg, numbers, name: "Host"))) {
                    case Answered(result) =>
                        if (result.status == MACRO_FAILED) {
                            throw IllegalStateException("macro expansion failed")
                        }
                        hosts.add(printMacroTokens(result.tks, numbers).text)
                    case Unanswered(reason) => throw IllegalStateException(reason)
                }
            }

            // assert - each macro returns its actual SDK process ID as a class name.
            @Expect(hosts[0].startsWith("class P"))
            @Expect(hosts.toArray(), Array<String>(4, repeat: hosts[0]))
        } finally {
            server.close()
            remove(root, recursive: true)
        }
    }
}
