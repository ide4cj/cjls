package cjls.handlers

import std.collection.ArrayList
import std.fs.{Path, remove}
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import stdxx.Nullable
import fjson.{JsonValue, RawJson}
import jsonrpc.*
import loupe.vfs.VfsPath
import cjls.lsp_types.*
import cjls.server.*

/**
 * A state as `initialize` leaves it for a client with `root` as its folder and `options` as its
 * `initializationOptions`, which answers `workspace/configuration` if `pulls`, and takes a
 * registration for `didChangeConfiguration` if `registers`.
 */
func initializedWithSettings(root: Path, options: ?JsonValue, pulls!: Bool = false, registers!: Bool = false): Loop {
    let state = ServerState()
    handleInitialize(state, Client(), NoopLogger(), InitializeParams(processId: Nullable.Null, rootUri: Nullable.Null,
        capabilities: ClientCapabilities(workspace: WorkspaceClientCapabilities(configuration: pulls,
            didChangeConfiguration: DidChangeConfigurationClientCapabilities(dynamicRegistration: registers))),
        workspaceFolders: Some(Nullable.Value([WorkspaceFolder(uri: uriOf(root), name: "ws")])),
        initializationOptions: options))
    Loop(state)
}

func linking(project: Path): JsonValue {
    JsonValue.JsonObject([("linkedProjects", JsonValue.JsonArray([JsonValue.JsonString(project.toString())]))])
}

/**
 * A transport that answers `workspace/configuration` with `section`, the section `cjls`, and any
 * other request with `null`.
 */
func configurationTransport(section: JsonValue): AnsweringTransport {
    AnsweringTransport(result: {
        request => if (request.method == ConfigurationRequestSpec.METHOD) {
            RawJson.of(JsonValue.JsonArray([section]))
        } else {
            RawJson.NULL
        }
    })
}

/**
 * The requests written to `transport`, taken from it.
 */
func requestsOf(transport: AnsweringTransport): Array<RequestBody> {
    let requests = ArrayList<RequestBody>()
    while (let Some(body) <- transport.written.tryRemove()) {
        if (let Request(request) <- body) {
            requests.add(request)
        }
    }
    requests.toArray()
}

func methodsOf(requests: Array<RequestBody>, method: String): Array<RequestBody> {
    requests.filter {request => request.method == method}
}

@Test
class InitialSettingsTest {
    @TestCase
    func theSettingsAreWhatInitializationOptionsHold() {
        // arrange
        let root = workspaceOf([])
        let linked = workspaceOf([("l.cj", "l")])

        // act
        let loop = initializedWithSettings(root, linking(linked))

        // assert
        @Expect(loop.state.settings.linkedProjects, [VfsPath.file(linked)])
        @Expect(!loop.state.pullsSettings)
        @Expect(!loop.state.registersSettings)
        remove(root, recursive: true)
        remove(linked, recursive: true)
    }

    @TestCase
    func optionsThatAreNoObjectOrNoneAreTheDefaults() {
        // arrange
        let root = workspaceOf([])

        // act
        let notAnObject = initializedWithSettings(root, JsonValue.JsonString("x"))
        let none = initializedWithSettings(root, Option<JsonValue>.None)

        // assert
        @Expect(notAnObject.state.settings == Settings())
        @Expect(none.state.settings == Settings())
        remove(root, recursive: true)
    }

    @TestCase
    func aClientThatAnswersConfigurationIsToldOfInTheState() {
        // arrange
        let root = workspaceOf([])

        // act
        let loop = initializedWithSettings(root, Option<JsonValue>.None, pulls: true, registers: true)

        // assert
        @Expect(loop.state.pullsSettings)
        @Expect(loop.state.registersSettings)
        remove(root, recursive: true)
    }
}

@Test
class PulledSettingsTest {
    @TestCase
    func theSectionCjlsIsAskedForOnceInitializedAndAChangeLoadsAgain() {
        // arrange
        let root = workspaceOf([("a.cj", "a")])
        let linked = workspaceOf([("l.cj", "l")])
        let loop = initializedWithSettings(root, Option<JsonValue>.None, pulls: true)
        let transport = configurationTransport(linking(linked))
        let client = answeredClientOn(transport)

        // act
        initialized(loop, client, NoopLogger(), InitializedParams())
        client.close()

        // assert
        let asked = methodsOf(requestsOf(transport), ConfigurationRequestSpec.METHOD)
        @Expect(asked.size, 1)
        @Expect(asked[0].params.getOrThrow().read<ConfigurationParams>().items[0].section, Some("cjls"))
        @Expect(loop.state.settings.linkedProjects, [VfsPath.file(linked)])
        @Expect(textAt(loop.state, linked.join("l.cj")), Some("l"))
        @Expect(textAt(loop.state, root.join("a.cj")), Some("a"))
        remove(root, recursive: true)
        remove(linked, recursive: true)
    }

    @TestCase[answer in [JsonValue.JsonNull, JsonValue.JsonObject([])]]
    func anAnswerOfNothingKeepsTheInitializationOptions(answer: JsonValue) {
        // arrange
        let root = workspaceOf([])
        let linked = workspaceOf([])
        let loop = initializedWithSettings(root, linking(linked), pulls: true)
        let transport = configurationTransport(answer)
        let client = answeredClientOn(transport)

        // act
        initialized(loop, client, NoopLogger(), InitializedParams())
        client.close()

        // assert
        @Expect(methodsOf(requestsOf(transport), ConfigurationRequestSpec.METHOD).size, 1)
        @Expect(loop.state.settings.linkedProjects, [VfsPath.file(linked)])
        remove(root, recursive: true)
        remove(linked, recursive: true)
    }

    @TestCase
    func anAnswerReplacesTheInitializationOptionsWhole() {
        // arrange
        let root = workspaceOf([])
        let linked = workspaceOf([])
        let sdk = workspaceOf([])
        let loop = initializedWithSettings(root, linking(linked), pulls: true)
        let client = answeredClientOn(configurationTransport(
            JsonValue.JsonObject([("cangjieHome", JsonValue.JsonString(sdk.toString()))])))

        // act
        initialized(loop, client, NoopLogger(), InitializedParams())
        client.close()

        // assert: a setting the answer leaves out is at its default
        @Expect(loop.state.settings == Settings(cangjieHome: sdk.toString()))
        remove(root, recursive: true)
        remove(linked, recursive: true)
        remove(sdk, recursive: true)
    }

    @TestCase
    func aClientThatAnswersIsAskedOnDidChangeConfigurationWhateverItSends() {
        // arrange
        let root = workspaceOf([])
        let linked = workspaceOf([("l.cj", "l")])
        let loop = initializedWithSettings(root, Option<JsonValue>.None, pulls: true)
        let transport = configurationTransport(linking(linked))
        let client = answeredClientOn(transport)

        // act
        handleDidChangeConfiguration(loop, client, NoopLogger(), DidChangeConfigurationParams(settings: JsonValue.JsonNull))
        loop.join()
        client.close()

        // assert
        @Expect(methodsOf(requestsOf(transport), ConfigurationRequestSpec.METHOD).size, 1)
        @Expect(loop.state.settings.linkedProjects, [VfsPath.file(linked)])
        @Expect(textAt(loop.state, linked.join("l.cj")), Some("l"))
        remove(root, recursive: true)
        remove(linked, recursive: true)
    }

    @TestCase
    func aRefusedAskingLeavesTheSettings() {
        // arrange
        let root = workspaceOf([])
        let linked = workspaceOf([])
        let loop = initializedWithSettings(root, linking(linked), pulls: true)
        let client = answeredClientOn(AnsweringTransport(refuses: true))

        // act
        handleDidChangeConfiguration(loop, client, NoopLogger(), DidChangeConfigurationParams(settings: JsonValue.JsonNull))
        loop.join()
        client.close()

        // assert
        @Expect(loop.state.settings.linkedProjects, [VfsPath.file(linked)])
        remove(root, recursive: true)
        remove(linked, recursive: true)
    }

    @TestCase
    func anAskingNotSentLeavesTheSettings() {
        // arrange
        let root = workspaceOf([])
        let linked = workspaceOf([])
        let loop = initializedWithSettings(root, linking(linked), pulls: true)

        // act: a client not connected takes no request
        handleDidChangeConfiguration(loop, Client(), NoopLogger(), DidChangeConfigurationParams(settings: JsonValue.JsonNull))
        loop.join()

        // assert
        @Expect(loop.state.settings.linkedProjects, [VfsPath.file(linked)])
        remove(root, recursive: true)
        remove(linked, recursive: true)
    }

    @TestCase
    func anAskingTheConnectionClosedOnLeavesTheSettings() {
        // arrange
        let root = workspaceOf([])
        let linked = workspaceOf([])
        let loop = initializedWithSettings(root, linking(linked), pulls: true)
        let transport = AnsweringTransport(answers: false)
        let client = answeredClientOn(transport)

        // act
        handleDidChangeConfiguration(loop, client, NoopLogger(), DidChangeConfigurationParams(settings: JsonValue.JsonNull))
        client.close()
        loop.join()

        // assert
        @Expect(methodsOf(requestsOf(transport), ConfigurationRequestSpec.METHOD).size, 1)
        @Expect(loop.state.settings.linkedProjects, [VfsPath.file(linked)])
        remove(root, recursive: true)
        remove(linked, recursive: true)
    }
}

@Test
class PushedSettingsTest {
    @TestCase
    func aClientThatCannotBeAskedPushesTheSectionCjls() {
        // arrange
        let root = workspaceOf([])
        let linked = workspaceOf([("l.cj", "l")])
        let loop = initializedWithSettings(root, Option<JsonValue>.None)
        let transport = configurationTransport(JsonValue.JsonNull)
        let client = answeredClientOn(transport)

        // act
        handleDidChangeConfiguration(loop, client, NoopLogger(),
            DidChangeConfigurationParams(settings: JsonValue.JsonObject([("cjls", linking(linked))])))
        loop.join()
        client.close()

        // assert
        @Expect(methodsOf(requestsOf(transport), ConfigurationRequestSpec.METHOD).size, 0)
        @Expect(loop.state.settings.linkedProjects, [VfsPath.file(linked)])
        @Expect(textAt(loop.state, linked.join("l.cj")), Some("l"))
        remove(root, recursive: true)
        remove(linked, recursive: true)
    }

    @TestCase[settings in [JsonValue.JsonNull, JsonValue.JsonObject([("other", JsonValue.JsonObject([]))]),
        JsonValue.JsonObject([("cjls", JsonValue.JsonString("x"))])]]
    func pushedSettingsWithoutTheSectionCjlsAsAnObjectChangeNothing(settings: JsonValue) {
        // arrange
        let root = workspaceOf([])
        let linked = workspaceOf([])
        let loop = initializedWithSettings(root, linking(linked))

        // act
        handleDidChangeConfiguration(loop, Client(), NoopLogger(), DidChangeConfigurationParams(settings: settings))
        loop.join()

        // assert
        @Expect(loop.state.settings.linkedProjects, [VfsPath.file(linked)])
        remove(root, recursive: true)
        remove(linked, recursive: true)
    }
}

@Test
class SettingsRegistrationTest {
    @TestCase
    func aClientThatTakesARegistrationIsAskedToTellOfTheSectionCjls() {
        // arrange
        let root = workspaceOf([])
        let loop = initializedWithSettings(root, Option<JsonValue>.None, registers: true)
        let transport = configurationTransport(JsonValue.JsonNull)
        let client = answeredClientOn(transport)

        // act
        initialized(loop, client, NoopLogger(), InitializedParams())
        client.close()

        // assert
        let registrations = methodsOf(requestsOf(transport), RegistrationRequestSpec.METHOD).flatMap {
            request => request.params.getOrThrow().read<RegistrationParams>().registrations
        }.filter {registration => registration.method == DidChangeConfigurationNotificationSpec.METHOD}
        @Expect(registrations.size, 1)
        let options = RawJson.of(registrations[0].registerOptions.getOrThrow())
            .read<DidChangeConfigurationRegistrationOptions>()
        @Expect(match (options.section) {
            case Some(StringOrStrings.AsString("cjls")) => true
            case _ => false
        })
        remove(root, recursive: true)
    }

    @TestCase
    func aClientThatTakesNoRegistrationIsAskedNothing() {
        // arrange
        let root = workspaceOf([])
        let loop = initializedWithSettings(root, Option<JsonValue>.None)
        let transport = configurationTransport(JsonValue.JsonNull)
        let client = answeredClientOn(transport)

        // act
        initialized(loop, client, NoopLogger(), InitializedParams())
        client.close()

        // assert
        let requests = requestsOf(transport)
        @Expect(methodsOf(requests, ConfigurationRequestSpec.METHOD).size, 0)
        let registered = methodsOf(requests, RegistrationRequestSpec.METHOD).flatMap {
            request => request.params.getOrThrow().read<RegistrationParams>().registrations
        }
        @Expect(!registered.any {registration => registration.method == DidChangeConfigurationNotificationSpec.METHOD})
        remove(root, recursive: true)
    }
}
