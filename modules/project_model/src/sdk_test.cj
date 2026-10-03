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

@When[os != "Windows"]
@Test
class FindCangjieHomeOnPosixTest {
    @TestCase
    func cjcOnPathIsFollowedThroughItsLinkToItsSdk() {
        // arrange
        let dir = tree([("sdk/bin/cjc", ""), ("empty/x", "")])
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
}
