package lsp_codegen

import std.collection.ArrayList

/**
 * LSP's `void`: the params of `exit`, the result of `shutdown`.
 */
const UNIT_TYPE = "Unit"

/**
 * The struct is the spec of the message, not the message itself.
 */
const SPEC_SUFFIX = "Spec"

struct MessageIr {
    MessageIr(
        let doc: DocIr,
        let ident!: String,
        let method!: String,
        let direction!: MessageDirection,
        /**
         * `None` for a message that takes none - `exit`.
         */
        let params!: ?TypeIr = None,
        /**
         * `None` for a request answered with a bare `null` - `shutdown` - and for a notification.
         */
        let result!: ?TypeIr = None,
        let isRequest!: Bool,
        /**
         * `None` for a message the server cannot register at run time.
         */
        let registrationOptions!: ?TypeIr = None,
        /**
         * The method a registration names, when it is not `method` - `textDocument/semanticTokens`.
         */
        let registrationMethod!: ?String = None
    ) {}

    prop paramsType: String {
        get() {
            params?.toString() ?? UNIT_TYPE
        }
    }

    prop resultType: String {
        get() {
            result?.toString() ?? UNIT_TYPE
        }
    }
}

/**
 * Runs before the declarations are collected: it meets unions and literals only messages use.
 */
func resolveMessages(resolver: TypeResolver, mm: MetaModel): Array<MessageIr> {
    let messages = ArrayList<MessageIr>()
    for (request in mm.requests) {
        let owner = messageIdentOf(request.typeName, request.method)
        // not declared yet, but resolved all the same: the types they name must exist
        resolveUnused(resolver, owner, [("PartialResult", request.partialResult), ("ErrorData", request.errorData)])
        messages.add(
            MessageIr(
                resolveDoc(request),
                ident: owner + SPEC_SUFFIX,
                method: request.method,
                direction: request.messageDirection,
                params: paramsOf(resolver, owner, request.params),
                result: resultOf(resolver, owner, request.result),
                isRequest: true,
                registrationOptions: optionalOf(resolver, owner + "RegistrationOptions", request.registrationOptions),
                registrationMethod: request.registrationMethod
            )
        )
    }
    for (notification in mm.notifications) {
        let owner = messageIdentOf(notification.typeName, notification.method)
        messages.add(
            MessageIr(
                resolveDoc(notification),
                ident: owner + SPEC_SUFFIX,
                method: notification.method,
                direction: notification.messageDirection,
                params: paramsOf(resolver, owner, notification.params),
                isRequest: false,
                registrationOptions: optionalOf(resolver, owner + "RegistrationOptions",
                    notification.registrationOptions),
                registrationMethod: notification.registrationMethod
            )
        )
    }

    messages.toArray()
}

/**
 * A name made up from the method could clash with a type, so a message without `typeName` is refused.
 */
private func messageIdentOf(typeName: ?String, method: String): String {
    typeName.getOrThrow {=> IllegalStateException("message `${method}` has no type name")}
}

private func paramsOf(resolver: TypeResolver, owner: String, params: ?OneOrMany<Type>): ?TypeIr {
    match (params) {
        case None => None
        case Some(One(t)) => resolver.resolve(t, context: owner + "Params")
        // positional params: LSP 3.x declares none, and a struct is no fit for them
        case Some(Many(_)) => throw IllegalStateException("`${owner}` takes its params by position")
    }
}

private func resultOf(resolver: TypeResolver, owner: String, result: Type): ?TypeIr {
    match (result) {
        case Base(Null) => None
        case _ => resolver.resolve(result, context: owner + "Result")
    }
}

private func optionalOf(resolver: TypeResolver, context: String, t: ?Type): ?TypeIr {
    match (t) {
        case Some(Base(Null)) | None => None
        case Some(some) => resolver.resolve(some, context: context)
    }
}

private func resolveUnused(resolver: TypeResolver, owner: String, types: Array<(String, ?Type)>): Unit {
    for ((part, t) in types) {
        optionalOf(resolver, owner + part, t)
    }
}

extend CjEmitter {
    func emitMessage(messageIr: MessageIr): Unit {
        let ident = escapedIdent(messageIr.ident).value
        let types = if (messageIr.isRequest) {
            "Request<${messageIr.paramsType}, ${messageIr.resultType}>"
        } else {
            "Notification<${messageIr.paramsType}>"
        }
        // the direction is in the type, so a handler of a message the server sends does not compile
        let (spec, isInbound, isOutbound) = match (messageIr.direction) {
            case ClientToServer => ("LspInbound${types}", true, false)
            case ServerToClient => ("LspOutbound${types}", false, true)
            case Both => ("LspInbound${types} & LspOutbound${types}", true, true)
        }
        let supertypes = match (messageIr.registrationOptions) {
            case Some(options) => "${spec} & LspRegistrable<${options}>"
            case None => spec
        }

        emitDoc(messageIr.doc)
        // verbatim: cjfmt leaves the spaces `Tokens` puts around `<` and `>` in a type
        emitln("public struct ${ident} <: ${supertypes} {")
        indented {
            =>
                emitln("public static prop METHOD: String {")
                indented {=> emitln("get() { \"${messageIr.method}\" }")}
                emitln("}")
                nl()
                emitln("public static prop DIRECTION: MessageDirection {")
                indented {=> emitln("get() { ${messageIr.direction} }")}
                emitln("}")
                nl()
                emitln("public prop method: String {")
                indented {=> emitln("get() { METHOD }")}
                emitln("}")
                if (messageIr.registrationOptions.isSome()) {
                    nl()
                    emitln("public prop registrationMethod: String {")
                    indented {
                        => match (messageIr.registrationMethod) {
                            case Some(registrationMethod) => emitln("get() { \"${registrationMethod}\" }")
                            case None => emitln("get() { METHOD }")
                        }
                    }
                    emitln("}")
                }
                if (isInbound) {
                    nl()
                    emitInboundCodec(messageIr)
                }
                if (isOutbound) {
                    nl()
                    emitOutboundCodec(messageIr)
                }
        }
        emitln("}")
    }

    /**
     * Written out per message rather than inherited: only here is it known whether there are params
     * to decode and a result to encode, and `Unit` - which stands for neither - can never be
     * `ToJson`, being a type of `std`.
     */
    private func emitInboundCodec(messageIr: MessageIr): Unit {
        emitln("public func decodeParams(params: ?RawJson): ${messageIr.paramsType} {")
        indented {
            => match (messageIr.params) {
                case Some(params) => emitln("decodeMessageParams<${params}>(params)")
                case None => emitln("()")
            }
        }
        emitln("}")
        nl()
        // in place, the value is there whatever the type: one without params skips it
        emitln("public func decodeParams(r: FjReader): ${messageIr.paramsType} {")
        indented {
            => match (messageIr.params) {
                case Some(params) => emitln("decodeMessageParams<${params}>(r)")
                case None => emitln("r.skipValue()")
            }
        }
        emitln("}")
        if (!messageIr.isRequest) {
            return
        }

        nl()
        emitln("public func encodeResult(result: ${messageIr.resultType}): RawJson {")
        indented {
            => match (messageIr.result) {
                case Some(_) => emitln("RawJson.of(result)")
                case None => emitln("RawJson.NULL")
            }
        }
        emitln("}")
    }

    /**
     * The other way round, for the same reason: params of none are `null`, which the connection
     * leaves out, and a bare `null` result is read as `()` whatever the client sends.
     */
    private func emitOutboundCodec(messageIr: MessageIr): Unit {
        emitln("public func encodeParams(params: ${messageIr.paramsType}): RawJson {")
        indented {
            => match (messageIr.params) {
                case Some(_) => emitln("RawJson.of(params)")
                case None => emitln("RawJson.NULL")
            }
        }
        emitln("}")
        if (!messageIr.isRequest) {
            return
        }

        nl()
        emitln("public func decodeResult(result: RawJson): ${messageIr.resultType} {")
        indented {
            => match (messageIr.result) {
                case Some(resultType) => emitln("result.read<${resultType}>()")
                case None => emitln("()")
            }
        }
        emitln("}")
    }
}
