package project_model

import std.collection.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * An environment of `vars` alone.
 */
func envOf(vars: Array<(String, String)>): (String) -> ?String {
    let map = HashMap<String, String>(vars)
    {name: String => map.get(name)}
}

@Test
class FindCangjieHomeTest {
    @TestCase
    func theOptionComesFirstThenCangjieHomeThenTheDefaultToolchain() {
        // arrange
        let dir = tree([("option/bin/x", ""), ("env/bin/x", ""), ("user/.cjpm/toolchains/default/bin/x", "")])
        let option = dir.join("option").toString()
        let env = envOf([("CANGJIE_HOME", dir.join("env").toString()), ("HOME", dir.join("user").toString())])

        // act
        let first = findCangjieHome(option, env: env)
        let noOption = findCangjieHome(None, env: env)
        let noVariable = findCangjieHome(dir.join("gone").toString(),
            env: envOf([("CANGJIE_HOME", dir.join("gone").toString()), ("HOME", dir.join("user").toString())]))
        let nothing = findCangjieHome(None, env: noEnv)
        removeTree(dir)

        // assert
        @Expect(first.map {home => home.path}, Some(option))
        @Expect(first.map {home => home.source}, Some("initializationOptions.cangjieHome"))
        @Expect(noOption.map {home => home.source}, Some("CANGJIE_HOME"))
        @Expect(noVariable.map {home => home.path},
            Some(Path(dir.join("user").toString()).join(".cjpm").join("toolchains").join("default").toString()))
        @Expect(nothing.isNone())
    }

    @TestCase
    func aRelativePathIsNoSdk() {
        // act, assert
        @Expect(findCangjieHome(".", env: envOf([("CANGJIE_HOME", ".")])).isNone())
    }

    @TestCase
    func cangjieHomeInAPathIsTheSdkFoundWhateverTheEnvironmentSays() {
        // arrange
        let env = withCangjieHome(envOf([("CANGJIE_HOME", "/elsewhere"), ("A", "a")]), CangjieHome("/sdk", "test"))
        let none = withCangjieHome(envOf([("CANGJIE_HOME", "/elsewhere")]), None)

        // act, assert
        @Expect(env("CANGJIE_HOME"), Some("/sdk"))
        @Expect(env("A"), Some("a"))
        @Expect(none("CANGJIE_HOME"), None<String>)
    }
}

@Test
class FindCangjieSrcTest {
    @TestCase
    func theOptionComesFirstThenCangjieSrcThenTheSdk() {
        // arrange
        let dir = tree([("option/std/std.cj", ""), ("env/std/std.cj", ""), ("sdk/src/std/std.cj", "")])
        let option = dir.join("option").toString()
        let env = envOf([("CANGJIE_SRC", dir.join("env").toString()), ("CANGJIE_HOME", dir.join("sdk").toString())])

        // act
        let first = findCangjieSrc(option, env: env)
        let noOption = findCangjieSrc(None, env: env)
        let noVariable = findCangjieSrc(None, env: envOf([("CANGJIE_HOME", dir.join("sdk").toString())]))
        let nothing = findCangjieSrc(None, env: noEnv)
        removeTree(dir)

        // assert
        @Expect(first.map {src => src.path}, Some(option))
        @Expect(first.map {src => src.source}, Some("initializationOptions.cangjieSrc"))
        @Expect(noOption.map {src => src.path}, Some(dir.join("env").toString()))
        @Expect(noOption.map {src => src.source}, Some("CANGJIE_SRC"))
        @Expect(noVariable.map {src => src.path}, Some(Path(dir.join("sdk").toString()).join("src").toString()))
        @Expect(noVariable.map {src => src.source}, Some("the SDK"))
        @Expect(nothing.isNone())
    }

    @TestCase
    func aDirectoryWithoutStdIsPassedOver() {
        // arrange
        let dir = tree([("option/stdx/x.cj", ""), ("sdk/src/std/std.cj", "")])
        let env = envOf([("CANGJIE_SRC", dir.join("gone").toString()), ("CANGJIE_HOME", dir.join("sdk").toString())])

        // act
        let src = findCangjieSrc(dir.join("option").toString(), env: env)
        removeTree(dir)

        // assert
        @Expect(src.map {it => it.source}, Some("the SDK"))
    }

    @TestCase
    func cangjieSrcIsTheSourcesFoundWhateverTheEnvironmentSays() {
        // arrange
        let env = withCangjieSrc(envOf([("CANGJIE_SRC", "/elsewhere"), ("A", "a")]), CangjieSrc("/src", "test"))
        let none = withCangjieSrc(envOf([("CANGJIE_SRC", "/elsewhere")]), None)

        // act, assert
        @Expect(env("CANGJIE_SRC"), Some("/src"))
        @Expect(env("A"), Some("a"))
        @Expect(none("CANGJIE_SRC"), None<String>)
    }
}

@When[os != "Windows"]
@Test
class FindCangjieHomeOnPosixTest {
    @TestCase
    func cjcOnPathIsFollowedThroughItsLinkToItsSdk() {
        // arrange
        let dir = tree([("sdk/bin/cjc", ""), ("sdk/modules/x", ""), ("empty/x", "")])
        Directory.create(dir.join("links").filePath.getOrThrow())
        SymbolicLink.create(dir.join("links/cjc").filePath.getOrThrow(), to: dir.join("sdk/bin/cjc").filePath.getOrThrow())
        let path = "relative:${dir.join("empty")}:${dir.join("links")}"

        // act
        let home = findCangjieHome(None, env: envOf([("PATH", path)]))
        let sdk = canonicalize(dir.join("sdk").filePath.getOrThrow()).toString()
        removeTree(dir)

        // assert
        @Expect(home.map {it => it.path}, Some(sdk))
        @Expect(home.map {it => it.source}, Some("cjc on PATH"))
    }

    @TestCase
    func aCjcWithNoSdkAroundItIsPassedOver() {
        // arrange: cjsdk's shim, `~/.local/bin/cjc` a link to `~/.local/bin/cjsdk`
        let dir = tree([("local/bin/cjsdk", "")])
        SymbolicLink.create(dir.join("local/bin/cjc").filePath.getOrThrow(),
            to: dir.join("local/bin/cjsdk").filePath.getOrThrow())

        // act
        let home = findCangjieHome(None, env: envOf([("PATH", dir.join("local/bin").toString())]))
        removeTree(dir)

        // assert
        @Expect(home.isNone())
    }

    @TestCase
    func anSdkCjsdkInstalledIsItsDefaultToolchain() {
        // arrange: as cjsdk installs one, `default` a link and `~/.local/bin/cjc` one to cjsdk itself
        let dir = tree([("user/.cjpm/toolchains/nightly/bin/cjc", ""), ("user/.cjpm/toolchains/nightly/modules/x", ""),
            ("user/.local/bin/cjsdk", "")])
        let toolchains = dir.join("user/.cjpm/toolchains")
        SymbolicLink.create(toolchains.join("default").filePath.getOrThrow(),
            to: toolchains.join("nightly").filePath.getOrThrow())
        SymbolicLink.create(dir.join("user/.local/bin/cjc").filePath.getOrThrow(),
            to: dir.join("user/.local/bin/cjsdk").filePath.getOrThrow())
        let env = envOf([("HOME", dir.join("user").toString()), ("PATH", dir.join("user/.local/bin").toString())])

        // act
        let home = findCangjieHome(None, env: env)
        removeTree(dir)

        // assert
        @Expect(home.map {it => it.path}, Some(toolchains.join("default").toString()))
        @Expect(home.map {it => it.source}, Some("the default toolchain of cjsdk"))
    }
}
