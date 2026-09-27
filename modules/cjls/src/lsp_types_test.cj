package cjls

import stdxx.serialization.*
import fjson.*
import jsonrpc.*
import cjls.lsp_types.*

private func read<T>(json: String): T where T <: FromJson<T> {
    fromJsonBytes<T>(json.toArray())
}

/**
 * What `value` writes, read into a tree for a test to look into.
 */
private func treeOf<T>(value: T): AnyValue where T <: ToJson {
    RawJson.of(value).read<AnyValue>()
}

/**
 * What the generated `lsp_types` make of messages as editors actually send them.
 */
@Test
class LspTypesTest {
    @TestCase
    func aRealInitializeRequestReads() {
        // arrange
        let json = ##"{
            "processId": 4242,
            "clientInfo": {"name": "Visual Studio Code", "version": "1.93.0"},
            "rootPath": null,
            "rootUri": "file:///home/user/project",
            "capabilities": {
                "textDocument": {
                    "hover": {"dynamicRegistration": true, "contentFormat": ["markdown", "plaintext"]},
                    "synchronization": {"didSave": true}
                },
                "general": {"positionEncodings": ["utf-16"]}
            },
            "trace": "off",
            "workspaceFolders": [{"uri": "file:///home/user/project", "name": "project"}]
        }"##

        // act
        let params = read<InitializeParams>(json)

        // assert
        @Expect(4242, params.processId.getOrThrow())
        @Expect("file:///home/user/project", params.rootUri.getOrThrow())
        @Expect(params.rootPath.getOrThrow().isNull())
        @Expect("project", params.workspaceFolders.getOrThrow().getOrThrow()[0].name)
        let hover = params.capabilities.textDocument.getOrThrow().hover.getOrThrow()
        @Expect(hover.dynamicRegistration.getOrThrow())
    }

    @TestCase
    func anAbsentOptionalIsLeftOutRatherThanWrittenAsNull() {
        // arrange
        let hover = Hover(contents: MarkupContentOrMarkedStringOrMarkedStrings.AsMarkupContent(
            MarkupContent(kind: MarkupKind.Markdown, value: "**x**")))

        // act
        let tree = treeOf(hover)

        // assert
        @Expect(tree.get("range").isNone())
        @Expect("markdown", tree["contents"]["kind"].asString())
    }

    @TestCase
    func aUnionTriesTheMemberRequiringMoreKeysFirst() {
        // arrange
        let command = ##"{"title": "Run", "command": "run"}"##
        let codeAction = ##"{"title": "Fix", "command": {"title": "Run", "command": "run"}}"##

        // act & assert
        @Expect(match (read<CommandOrCodeAction>(command)) {
            case AsCommand(c) => c.command == "run"
            case _ => false
        })
        @Expect(match (read<CommandOrCodeAction>(codeAction)) {
            case AsCodeAction(a) => a.title == "Fix"
            case _ => false
        })
    }

    @TestCase
    func theKindTagPicksTheFileOperation() {
        // arrange
        let delete = ##"{"uri": "file:///a", "kind": "delete"}"##

        // act
        let change = read<TextDocumentEditOrCreateFileOrRenameFileOrDeleteFile>(delete)

        // assert
        @Expect(match (change) {
            case AsDeleteFile(d) => d.uri == "file:///a"
            case _ => false
        })
        @Expect("delete", treeOf(change)["kind"].asString())
    }

    @TestCase
    func aParameterLabelIsEitherAStringOrAnOffsetPair() {
        // arrange
        let byOffsets = ##"{"label": [4, 9]}"##

        // act
        let info = read<ParameterInformation>(byOffsets)

        // assert
        @Expect(match (info.label) {
            case AsUIntegerPair(start, end) => start == 4 && end == 9
            case _ => false
        })
        @Expect(match (read<ParameterInformation>(##"{"label": "x"}"##).label) {
            case AsString(s) => s == "x"
            case _ => false
        })
    }

    @TestCase
    func anEnumValueNewerThanTheMetaModelSurvives() {
        // arrange
        let json = ##"{"range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 1}},
            "message": "m", "severity": 1, "tags": [1, 99]}"##

        // act
        let diagnostic = read<Diagnostic>(json)

        // assert
        @Expect(match (diagnostic.tags.getOrThrow()[1]) {
            case Unknown(99) => true
            case _ => false
        })
    }

    @TestCase
    func aSpecDecodesItsParamsAndEncodesItsResult() {
        // arrange
        let spec = InitializeRequestSpec()
        let params = RawJson(##"{"processId": 42, "rootUri": null, "capabilities": {}}"##.toArray())

        // act
        let decoded = spec.decodeParams(params)
        let encoded = spec.encodeResult(InitializeResult(capabilities: ServerCapabilities(),
            serverInfo: ServerInfo(name: "cjls")))

        // assert
        @Expect("initialize", spec.method)
        @Expect(42, decoded.processId.getOrThrow())
        let serverInfo = encoded.read<AnyValue>()["serverInfo"]
        @Expect("cjls", serverInfo["name"].asString())
    }

    @TestCase
    func paramsThatDoNotReadAreInvalidParams() {
        // arrange - `capabilities` is required
        let params = RawJson(##"{"processId": 1, "rootUri": null}"##.toArray())

        // act
        let e = @AssertThrows[RpcException](InitializeRequestSpec().decodeParams(params))

        // assert
        @Expect(ErrorCode.INVALID_PARAMS, e.code)
    }

    @TestCase
    func aMessageWithoutParamsOrResultTakesAbsentParamsAndAnswersNull() {
        // act - its params and result are `Unit`, nothing to read or write
        ExitNotificationSpec().decodeParams(Option<RawJson>.None)
        ShutdownRequestSpec().decodeParams(Option<RawJson>.None)
        let result = ShutdownRequestSpec().encodeResult(())

        // assert
        @Expect("null", result.toString())
    }
}
