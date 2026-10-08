package lsp_codegen

import std.unittest.*
import std.unittest.testmacro.*

private func resolveMessagesOf(requests!: Array<Request> = [], notifications!: Array<Notification> = []): Array<
    MessageIr> {
    let mm = metaModelOf(requests: requests, notifications: notifications)

    resolveMessages(TypeResolver(mm, configOf()), mm)
}

private func requestOf(method: String, typeName: String, result: Type, params!: ?OneOrMany<Type> = None): Request {
    Request(method: method, typeName: typeName, params: params, result: result,
        messageDirection: MessageDirection.ClientToServer)
}

private func emittedMessage(messageIr: MessageIr): String {
    emittedBy {emitter => emitter.emitMessage(messageIr)}
}

@Test
class ResolveMessagesTest {
    @TestCase
    func aRequestNamesItsParamsAndResultTypes() {
        // act
        let messages = resolveMessagesOf(
            requests: [requestOf("textDocument/hover", "HoverRequest",
                Type.Or([Type.Reference("Hover"), Type.Base(BaseTypes.Null)]),
                params: OneOrMany.One(Type.Reference("HoverParams")))])

        // assert
        @Expect("HoverRequestSpec", messages[0].ident)
        @Expect("textDocument/hover", messages[0].method)
        @Expect("HoverParams", messages[0].paramsType)
        @Expect("Nullable<Hover>", messages[0].resultType)
    }

    @TestCase
    func noParamsAndANullResultAreBothUnit() {
        // act - `shutdown`
        let messages = resolveMessagesOf(requests: [requestOf("shutdown", "ShutdownRequest", Type.Base(BaseTypes.Null))])

        // assert
        @Expect("Unit", messages[0].paramsType)
        @Expect("Unit", messages[0].resultType)
    }

    @TestCase
    func aNotificationHasNoResult() {
        // act
        let messages = resolveMessagesOf(
            notifications: [Notification(method: "exit", typeName: "ExitNotification",
                messageDirection: MessageDirection.ClientToServer)])

        // assert
        @Expect(!messages[0].isRequest)
        @Expect("Unit", messages[0].paramsType)
    }

    @TestCase
    func registrationOptionsAndTheMethodRegisteredUnderAreResolved() {
        // act
        let messages = resolveMessagesOf(
            requests: [Request(method: "textDocument/semanticTokens/full", typeName: "SemanticTokensRequest",
                result: Type.Base(BaseTypes.Null), registrationMethod: "textDocument/semanticTokens",
                registrationOptions: Type.Reference("SemanticTokensRegistrationOptions"),
                messageDirection: MessageDirection.ClientToServer)],
            notifications: [Notification(method: "exit", typeName: "ExitNotification",
                messageDirection: MessageDirection.ClientToServer)])

        // assert
        @Expect("SemanticTokensRegistrationOptions", messages[0].registrationOptions.getOrThrow().toString())
        @Expect("textDocument/semanticTokens", messages[0].registrationMethod.getOrThrow())
        @Expect(messages[1].registrationOptions.isNone())
    }

    @TestCase
    func positionalParamsAreRefused() {
        // act & assert - LSP 3.x declares none
        @AssertThrows[IllegalStateException](resolveMessagesOf(
            requests: [requestOf("odd", "OddRequest", Type.Base(BaseTypes.Null),
                params: OneOrMany.Many([Type.Reference("A"), Type.Reference("B")]))]))
    }
}

@Test
class EmitMessageTest {
    @TestCase
    func aMessageIsEmittedAsASpecOfItsTypes() {
        // arrange
        let messageIr = MessageIr(DocIr(), ident: "HoverRequestSpec", method: "textDocument/hover",
            direction: MessageDirection.ClientToServer, params: TypeIr.Named("HoverParams"),
            result: TypeIr.NullableOf(TypeIr.Named("Hover")), isRequest: true)

        // act
        let emitted = emittedMessage(messageIr)

        // assert
        @Expect(emitted.contains("public struct HoverRequestSpec <: LspInboundRequest<HoverParams, Nullable<Hover>> {"))
        @Expect(emitted.contains("\"textDocument/hover\""))
        @Expect(emitted.contains("MessageDirection.ClientToServer"))
        @Expect(emitted.contains("decodeMessageParams<HoverParams>(params)"))
        @Expect(emitted.contains("public func encodeResult(result: Nullable<Hover>): RawJson {"))
    }

    @TestCase
    func aMessageWithoutParamsOrResultIsBoundToUnit() {
        // arrange - `shutdown`
        let messageIr = MessageIr(DocIr(), ident: "ShutdownRequestSpec", method: "shutdown",
            direction: MessageDirection.ClientToServer, isRequest: true)

        // act
        let emitted = emittedMessage(messageIr)

        // assert
        @Expect(emitted.contains("LspInboundRequest<Unit, Unit>"))
        @Expect(emitted.contains("public func decodeParams(params: ?RawJson): Unit {"))
        @Expect(emitted.contains("RawJson.NULL"))
    }

    @TestCase
    func aNotificationTheServerSendsEncodesItsParamsOnly() {
        // arrange
        let messageIr = MessageIr(DocIr(), ident: "ShowMessageNotificationSpec", method: "window/showMessage",
            direction: MessageDirection.ServerToClient, params: TypeIr.Named("ShowMessageParams"), isRequest: false)

        // act
        let emitted = emittedMessage(messageIr)

        // assert
        @Expect(emitted.contains("LspOutboundNotification<ShowMessageParams>"))
        @Expect(emitted.contains("public func encodeParams(params: ShowMessageParams): RawJson {"))
        @Expect(emitted.contains("RawJson.of(params)"))
        @Expect(!emitted.contains("decodeParams"))
        @Expect(!emitted.contains("decodeResult"))
    }

    @TestCase
    func aRequestTheServerSendsEncodesItsParamsAndDecodesItsResult() {
        // arrange
        let messageIr = MessageIr(DocIr(), ident: "ConfigurationRequestSpec", method: "workspace/configuration",
            direction: MessageDirection.ServerToClient, params: TypeIr.Named("ConfigurationParams"),
            result: TypeIr.ArrayOf(TypeIr.Named("LSPAny")), isRequest: true)

        // act
        let emitted = emittedMessage(messageIr)

        // assert
        @Expect(emitted.contains("LspOutboundRequest<ConfigurationParams, Array<LSPAny>>"))
        @Expect(emitted.contains("public func decodeResult(result: RawJson): Array<LSPAny> {"))
        @Expect(emitted.contains("result.read<Array<LSPAny>>()"))
        @Expect(!emitted.contains("encodeResult"))
    }

    @TestCase
    func aRequestTheServerSendsWithoutParamsOrResultWritesNullAndReadsUnit() {
        // arrange - `workspace/semanticTokens/refresh`
        let messageIr = MessageIr(DocIr(), ident: "SemanticTokensRefreshRequestSpec",
            method: "workspace/semanticTokens/refresh", direction: MessageDirection.ServerToClient, isRequest: true)

        // act
        let emitted = emittedMessage(messageIr)

        // assert
        @Expect(emitted.contains("LspOutboundRequest<Unit, Unit>"))
        @Expect(emitted.contains("public func encodeParams(params: Unit): RawJson {"))
        @Expect(emitted.contains("RawJson.NULL"))
        @Expect(emitted.contains("public func decodeResult(result: RawJson): Unit {"))
    }

    @TestCase
    func aMessageWithRegistrationOptionsIsRegistrableUnderItsRegistrationMethod() {
        // arrange
        let messageIr = MessageIr(DocIr(), ident: "SemanticTokensDeltaRequestSpec",
            method: "textDocument/semanticTokens/full/delta", direction: MessageDirection.ClientToServer,
            params: TypeIr.Named("SemanticTokensDeltaParams"), result: TypeIr.Named("SemanticTokensDelta"),
            isRequest: true, registrationOptions: TypeIr.Named("SemanticTokensRegistrationOptions"),
            registrationMethod: "textDocument/semanticTokens")

        // act
        let emitted = emittedMessage(messageIr)

        // assert
        @Expect(emitted.contains("& LspRegistrable<SemanticTokensRegistrationOptions> {"))
        @Expect(emitted.contains("public prop registrationMethod: String {"))
        @Expect(emitted.contains("\"textDocument/semanticTokens\""))
    }

    @TestCase
    func aMessageWithoutRegistrationOptionsIsNotRegistrable() {
        // arrange
        let messageIr = MessageIr(DocIr(), ident: "ShutdownRequestSpec", method: "shutdown",
            direction: MessageDirection.ClientToServer, isRequest: true)

        // act
        let emitted = emittedMessage(messageIr)

        // assert
        @Expect(!emitted.contains("LspRegistrable"))
        @Expect(!emitted.contains("registrationMethod"))
    }

    @TestCase
    func aMessageSentBothWaysIsBothInboundAndOutbound() {
        // arrange - `$/progress`
        let messageIr = MessageIr(DocIr(), ident: "ProgressNotificationSpec", method: "$/progress",
            direction: MessageDirection.Both, params: TypeIr.Named("ProgressParams"), isRequest: false)

        // act
        let emitted = emittedMessage(messageIr)

        // assert
        @Expect(emitted.contains(
            "ProgressNotificationSpec <: LspInboundNotification<ProgressParams> & LspOutboundNotification<ProgressParams>"))
        @Expect(emitted.contains("public func decodeParams(params: ?RawJson): ProgressParams {"))
        @Expect(emitted.contains("public func encodeParams(params: ProgressParams): RawJson {"))
    }
}
