package cjls.server

import std.collection.ArrayList
import std.env.getTempDirectory
import std.unittest.*
import std.unittest.testmacro.*
import fjson.JsonValue
import loupe.vfs.VfsPath

func settingsJson(members: Array<(String, JsonValue)>): JsonValue {
    JsonValue.JsonObject(members)
}

func text(value: String): JsonValue {
    JsonValue.JsonString(value)
}

@Test
class SettingsTest {
    @TestCase
    func eachSettingIsReadAsAnAbsolutePathOrAFileUri() {
        // arrange
        let a = getTempDirectory().join("a")
        let b = getTempDirectory().join("b").join("cj-project.json")
        let sdk = getTempDirectory().join("sdk")
        let src = getTempDirectory().join("src")
        let problems = ArrayList<String>()

        // act
        let settings = Settings.read(settingsJson([
            ("linkedProjects", JsonValue.JsonArray([text(a.toString()), text(VfsPath.file(b).toUri())])),
            ("cangjieHome", text(VfsPath.file(sdk).toUri())),
            ("cangjieSrc", text(src.toString()))
        ]), problems)

        // assert
        @Expect(settings.linkedProjects, [VfsPath.file(a), VfsPath.file(b)])
        @Expect(settings.cangjieHome, VfsPath.file(sdk).filePath.map {it => it.toString()})
        @Expect(settings.cangjieSrc, Some(src.toString()))
        @Expect(problems.size, 0)
    }

    @TestCase
    func aSettingAbsentOrNullIsAtItsDefault() {
        // arrange
        let problems = ArrayList<String>()

        // act
        let settings = Settings.read(settingsJson([("cangjieHome", JsonValue.JsonNull), ("other", text("x"))]),
            problems)

        // assert
        @Expect(settings == Settings())
        @Expect(problems.size, 0)
    }

    @TestCase
    func aValueNotOfItsSchemaIsAtItsDefaultAndToldOf() {
        // arrange
        let a = getTempDirectory().join("a")
        let problems = ArrayList<String>()

        // act
        let settings = Settings.read(settingsJson([
            ("linkedProjects", JsonValue.JsonArray([text("relative"), text(a.toString()), JsonValue.JsonInteger(1)])),
            ("cangjieHome", text("relative")),
            ("cangjieSrc", JsonValue.JsonBool(true))
        ]), problems)

        // assert: an item of a list is left out alone
        @Expect(settings == Settings(linkedProjects: [VfsPath.file(a)]))
        @Expect(problems.size, 4)
        @Expect(problems.toArray().filter {problem => problem.contains("`linkedProjects`")}.size, 2)
        @Expect(problems[2].contains("`cangjieHome`"))
        @Expect(problems[3].contains("`cangjieSrc`"))
    }

    @TestCase
    func everyPropertyOfTheSchemaIsASettingRead() {
        // arrange
        let properties = settingsSchema()["properties"].asObject()

        // act, assert: a value no setting takes is told of, under its key
        for ((key, _) in properties) {
            let problems = ArrayList<String>()
            Settings.read(settingsJson([(key, settingsJson([("not", text("this"))]))]), problems)
            @Expect(problems.size, 1)
            @Expect(problems[0].contains("`${key}`"))
        }
        @Expect(properties.map {property => property[0]}, ["linkedProjects", "cangjieHome", "cangjieSrc"])
    }

    @TestCase
    func everyPropertyOfTheSchemaHasATypeADefaultAndADescription() {
        // act
        let schema = settingsSchema()

        // assert
        @Expect(schema["type"], text("object"))
        for ((_, property) in schema["properties"].asObject()) {
            @Expect(property.get("type").isSome())
            @Expect(property.get("default").isSome())
            @Expect(property.get("description").isSome())
        }
    }
}

@Test
class SettingsPullTest {
    @TestCase
    func onlyTheLastPullIsTaken() {
        // arrange
        let state = ServerState()

        // act
        let first = state.beginSettingsPull()
        let second = state.beginSettingsPull()

        // assert
        @Expect(!state.isLastSettingsPull(first))
        @Expect(state.isLastSettingsPull(second))
    }
}
