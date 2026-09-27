package stdxx

import std.deriving.*
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import ftoml.*
import stdxx.deriving.*

// A manifest in the manner of `cjpm.toml`: what the generators' configurations will be read as.

@DeriveExt[ToToml, FromToml]
struct TomlManifest {
    TomlManifest(
        let `package`!: TomlPackage,
        let dependencies!: ?HashMap<String, TomlDependency> = None,
        let bin!: ?Array<TomlTarget> = None,
        let profile!: ?TomlProfile = None
    ) {}
}

@DeriveExt[ToToml, FromToml]
struct TomlPackage {
    TomlPackage(
        let name!: String,
        @Serde[rename: "cjc-version"] let cjcVersion!: String,
        @Serde[rename: "output-type"] let outputType!: TomlOutputType,
        let description!: ?String = None,
        let members!: ?Array<String> = None
    ) {}
}

@DeriveExt[ToToml, FromToml]
struct TomlTarget {
    TomlTarget(let name!: String, let level!: TomlLevel) {}
}

@DeriveExt[ToToml, FromToml]
struct TomlProfile {
    TomlProfile(let lto!: Bool, let jobs!: Int64) {}
}

@DeriveExt[ToToml, FromToml]
@Serde[tag: "kind", rename: "path"]
@Derive[Equatable]
struct TomlPathDependency {
    TomlPathDependency(let path!: String) {}
}

@DeriveExt[ToToml, FromToml]
@Serde[untagged]
@Derive[Equatable]
enum TomlDependency {
    | Version(String)
    | Local(TomlPathDependency)
}

@DeriveExt[ToToml, FromToml]
@Derive[Equatable]
enum TomlOutputType {
    | @Serde[rename: "static"]
    StaticLib
    | @Serde[rename: "dynamic"]
    DynamicLib
    | Executable
    | @Serde[other]
    OutputOf(String)
}

@DeriveExt[ToToml, FromToml]
@Derive[Equatable]
enum TomlLevel {
    | @Serde[value: 0]
    Quiet
    | @Serde[value: 2]
    Loud
    | @Serde[other]
    LevelOf(UInt32)
}

@DeriveExt[ToToml, FromToml]
@Serde[untagged]
@Derive[Equatable]
enum TomlRange {
    | At(Int64)
    | Between(Int64, Int64)
}

@DeriveExt[ToToml, FromToml]
@Serde[tag: "kind"]
@Derive[Equatable]
enum TomlStep {
    | @Serde[rename: "run", payload: ["command", "args"]]
    Run(String, Array<String>)
    | @Serde[rename: "echo", payload: ["text", "to"]]
    Echo(String, ?String)
    | @Serde[rename: "skip"]
    Skip
}

@DeriveExt[ToToml, FromToml]
@Serde[transparent]
@Derive[Equatable]
struct TomlVersion {
    TomlVersion(let value: String) {}
}

@DeriveExt[ToToml, FromToml]
struct TomlBox<T> {
    TomlBox(let value!: T) {}
}

@DeriveExt[ToToml, FromToml]
struct TomlPositional {
    TomlPositional(let x: Int64, let y: Int64) {}
}

@DeriveExt[ToToml, FromToml]
struct TomlSteps {
    TomlSteps(let steps!: Array<TomlStep>, let range!: ?TomlRange = None, let version!: ?TomlVersion = None) {}
}

private func toml<T>(value: T): String where T <: ToToml {
    toTomlString(value)
}

private func read<T>(text: String): T where T <: FromToml<T> {
    fromTomlString<T>(text)
}

private let PACKAGE = TomlPackage(name: "cjls", cjcVersion: "1.3.0", outputType: TomlOutputType.Executable)

@Test
class DeriveTomlStructTest {
    @TestCase
    func plainKeysAreWrittenInDeclarationOrderAndNoneNotAtAll() {
        // act & assert
        @Expect(toml(PACKAGE), "name = \"cjls\"\ncjc-version = \"1.3.0\"\noutput-type = \"Executable\"\n")
    }

    @TestCase
    func tablesAndArraysOfTablesGoUnderHeadersAfterThePlainKeys() {
        // arrange
        let dependencies = HashMap<String, TomlDependency>()
        dependencies["fjson"] = TomlDependency.Local(TomlPathDependency(path: "../fjson"))
        let manifest = TomlManifest(
            `package`: PACKAGE,
            dependencies: dependencies,
            bin: [TomlTarget(name: "a", level: TomlLevel.Quiet)],
            profile: TomlProfile(lto: false, jobs: 4)
        )

        // act & assert
        @Expect(toml(manifest),
            "[package]\nname = \"cjls\"\ncjc-version = \"1.3.0\"\noutput-type = \"Executable\"\n" +
            "\n[dependencies]\n\n[dependencies.fjson]\nkind = \"path\"\npath = \"../fjson\"\n" +
            "\n[[bin]]\nname = \"a\"\nlevel = 0\n" + "\n[profile]\nlto = false\njobs = 4\n")
    }

    @TestCase
    func anEmptyArrayOfTablesIsAPlainKey() {
        // act & assert
        @Expect(toml(TomlManifest(`package`: PACKAGE, bin: [])).startsWith("bin = []\n\n[package]\n"))
    }

    @TestCase
    func aManifestRoundTrips() {
        // arrange
        let text = "[package]\nname = \"cjls\"\ncjc-version = \"1.3.0\"\noutput-type = \"static\"\n" +
            "members = [\"a\", \"b\"]\n\n[dependencies]\nfjson = { kind = \"path\", path = \"../fjson\" }\n" +
            "rope = \"1.0\"\n\n[[bin]]\nname = \"x\"\nlevel = 7\n"

        // act
        let manifest = read<TomlManifest>(text)
        let restored = read<TomlManifest>(toml(manifest))

        // assert
        for (m in [manifest, restored]) {
            @Expect(m.`package`.outputType, TomlOutputType.StaticLib)
            @Expect(m.`package`.members, Some(["a", "b"]))
            @Expect(m.`package`.description, None<String>)
            let dependencies = m.dependencies.getOrThrow()
            @Expect(dependencies["fjson"], TomlDependency.Local(TomlPathDependency(path: "../fjson")))
            @Expect(dependencies["rope"], TomlDependency.Version("1.0"))
            @Expect(m.bin.getOrThrow()[0].level, TomlLevel.LevelOf(7))
            @Expect(m.profile.isNone())
        }
    }

    @TestCase
    func keysAreReadInAnyOrderAndUnknownOnesSkipped() {
        // act
        let target = read<TomlTarget>("extra = {a = [1, \"x\"]}\nlevel = 2\nname = \"t\"\n")

        // assert
        @Expect(target.name, "t")
        @Expect(target.level, TomlLevel.Loud)
    }

    @TestCase
    func aMissingKeyThrowsNamingItAtItsTable() {
        // act
        let e = @AssertThrows[FtException](read<TomlManifest>("[bin]\n\n[package]\nname = \"x\"\n"))

        // assert
        @Expect(e.reason, "`TomlPackage` misses the key \"cjc-version\"")
        @Expect(e.line, 3)
        @Expect(e.column, 1)
    }

    @TestCase
    func aValueOfTheWrongKindThrowsWhereItIs() {
        // act
        let e = @AssertThrows[FtException](read<TomlProfile>("lto = false\njobs = \"4\"\n"))

        // assert
        @Expect(e.line, 2)
        @Expect(e.column, 8)
    }

    @TestCase
    func positionalFieldsRoundTrip() {
        // act
        let restored = read<TomlPositional>(toml(TomlPositional(1, 2)))

        // assert
        @Expect(restored.x, 1)
        @Expect(restored.y, 2)
    }

    @TestCase
    func aGenericFieldTakesItsShapeFromItsType() {
        // act & assert
        @Expect(toml(TomlBox(value: "boxed")), "value = \"boxed\"\n")
        @Expect(toml(TomlBox(value: TomlProfile(lto: true, jobs: 1))), "[value]\nlto = true\njobs = 1\n")
        @Expect(read<TomlBox<Int64>>("value = 3").value, 3)
    }

    @TestCase
    func aDocumentIsATable() {
        // act & assert
        @AssertThrows[FtException](toml(TomlVersion("1.0")))
    }
}

@Test
class DeriveTomlEnumTest {
    @TestCase
    func aScalarEnumIsItsNameOrItsValue() {
        // act & assert
        @Expect(toml(TomlTarget(name: "t", level: TomlLevel.Loud)), "name = \"t\"\nlevel = 2\n")
        @Expect(read<TomlBox<TomlOutputType>>("value = \"dynamic\"").value, TomlOutputType.DynamicLib)
        @Expect(read<TomlBox<TomlOutputType>>("value = \"Executable\"").value, TomlOutputType.Executable)
    }

    @TestCase
    func anUnknownValueIsKeptByOtherAndWrittenBack() {
        // act
        let output = read<TomlBox<TomlOutputType>>("value = \"wasm\"").value
        let level = read<TomlBox<TomlLevel>>("value = 9").value

        // assert
        @Expect(output, TomlOutputType.OutputOf("wasm"))
        @Expect(toml(TomlBox(value: output)), "value = \"wasm\"\n")
        @Expect(level, TomlLevel.LevelOf(9))
        @Expect(toml(TomlBox(value: level)), "value = 9\n")
    }

    @TestCase
    func aValueOutsideTheOtherPayloadThrows() {
        // act
        let e = @AssertThrows[FtException](read<TomlBox<TomlLevel>>("value = -1"))

        // assert
        @Expect(e.reason, "`TomlLevel` value out of range: -1")
        @AssertThrows[FtException](read<TomlBox<TomlLevel>>("value = \"1\""))
    }

    @TestCase
    func anUntaggedVariantIsWhicheverTheValueReadsAs() {
        // act & assert
        @Expect(read<TomlSteps>("steps = []\nrange = 3").range, Some(TomlRange.At(3)))
        @Expect(read<TomlSteps>("steps = []\nrange = [3, 7]").range, Some(TomlRange.Between(3, 7)))
        @Expect(toml(TomlSteps(steps: [], range: TomlRange.Between(3, 7))), "steps = []\nrange = [3, 7]\n")
    }

    @TestCase
    func aValueMatchingNoUntaggedVariantThrows() {
        // act
        let e = @AssertThrows[FtException](read<TomlSteps>("steps = []\nrange = [1, 2, 3]"))

        // assert
        @Expect(e.reason, "no `TomlRange` variant matched the value")
        @Expect(e.line, 2)
    }

    @TestCase
    func anUntaggedVariantHoldingATableIsWrittenUnderAHeader() {
        // arrange
        let dependencies = HashMap<String, TomlDependency>()
        dependencies["a"] = TomlDependency.Local(TomlPathDependency(path: "a"))
        dependencies["b"] = TomlDependency.Version("1")

        // act & assert
        @Expect(toml(TomlBox(value: dependencies)), "[value]\nb = \"1\"\n\n[value.a]\nkind = \"path\"\npath = \"a\"\n")
    }

    @TestCase
    func aTaggedVariantIsATableOfTheTagAndItsPayloads() {
        // arrange
        let steps = TomlSteps(steps: [TomlStep.Run("cjpm", ["test"]), TomlStep.Echo("hi", None), TomlStep.Skip])

        // act
        let text = toml(steps)

        // assert
        @Expect(text,
            "[[steps]]\nkind = \"run\"\ncommand = \"cjpm\"\nargs = [\"test\"]\n" +
            "\n[[steps]]\nkind = \"echo\"\ntext = \"hi\"\n" + "\n[[steps]]\nkind = \"skip\"\n")
        @Expect(read<TomlSteps>(text).steps, steps.steps)
    }

    @TestCase
    func theTagIsFoundWhereverItIs() {
        // act & assert
        @Expect(read<TomlBox<TomlStep>>("value = {to = \"err\", text = \"x\", kind = \"echo\"}").value,
            TomlStep.Echo("x", "err"))
    }

    @TestCase
    func anUnknownOrAbsentTagThrows() {
        // act
        let unknown = @AssertThrows[FtException](read<TomlBox<TomlStep>>("value = {kind = \"jump\"}"))
        let absent = @AssertThrows[FtException](read<TomlBox<TomlStep>>("value = {text = \"x\"}"))

        // assert
        @Expect(unknown.reason, "unexpected `TomlStep` kind: jump")
        @Expect(absent.reason, "`TomlStep` misses the key \"kind\"")
    }
}

@Test
class DeriveTomlTransparentAndTaggedStructTest {
    @TestCase
    func aTransparentStructIsItsOnlyField() {
        // act & assert
        @Expect(toml(TomlSteps(steps: [], version: TomlVersion("1.0"))), "steps = []\nversion = \"1.0\"\n")
        @Expect(read<TomlSteps>("steps = []\nversion = \"2\"").version, Some(TomlVersion("2")))
        @AssertThrows[FtException](read<TomlSteps>("steps = []\nversion = 2"))
    }

    @TestCase
    func aForeignOrAbsentTagThrows() {
        // act
        let onOtherTag = @AssertThrows[FtException](read<TomlPathDependency>("kind = \"git\"\npath = \"a\""))
        let absent = @AssertThrows[FtException](read<TomlPathDependency>("path = \"a\""))

        // assert
        @Expect(onOtherTag.reason, "unexpected `TomlPathDependency` kind: git")
        @Expect(absent.reason, "`TomlPathDependency` misses the key \"kind\"")
    }
}
