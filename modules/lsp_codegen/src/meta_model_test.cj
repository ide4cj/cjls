package lsp_codegen

import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonFloat, JsonInt, JsonNull, JsonObject, JsonString, JsonValue}
import fjson.{FromJson, ToJson, fromJsonBytes, toJsonBytes}

/**
 * A meta model of these declarations alone.
 */
func metaModelOf(
    requests!: Array<Request> = [],
    notifications!: Array<Notification> = [],
    structures!: Array<Structure> = [],
    typeAliases!: Array<TypeAlias> = [],
    enumerations!: Array<Enumeration> = []
): MetaModel {
    MetaModel(metaData: MetaData(version: "3.18.0"), requests: requests, notifications: notifications,
        structures: structures, enumerations: enumerations, typeAliases: typeAliases)
}

private func treeOf(json: String): JsonValue {
    JsonValue.fromStr(json)
}

/**
 * The text read as `T` and written back, as stdx reads it: an oracle `fjson` has no part in.
 */
private func rewrittenAs<T>(json: String): JsonValue where T <: ToJson & FromJson<T> {
    treeOf(String.fromUtf8(toJsonBytes(fromJsonBytes<T>(json.toArray()))))
}

/**
 * The path of the first difference, or `None` when the two are equal by JSON rules - object
 * members unordered, arrays in order. `toJson` writes the fields in declaration order, so comparing
 * the texts would fail on a key order that means nothing.
 */
private func firstDifference(expected: JsonValue, actual: JsonValue, path!: String = "$"): ?String {
    match ((expected, actual)) {
        case (e: JsonObject, a: JsonObject) =>
            let expectedFields = e.getFields()
            let actualFields = a.getFields()
            for ((name, expectedValue) in expectedFields) {
                match (actualFields.get(name)) {
                    case None => return "${path}.${name} (dropped on the way out)"
                    case Some(actualValue) =>
                        if (let Some(diff) <- firstDifference(expectedValue, actualValue, path: "${path}.${name}")) {
                            return diff
                        }
                }
            }
            for ((name, _) in actualFields) {
                if (expectedFields.get(name).isNone()) {
                    return "${path}.${name} (invented on the way out)"
                }
            }
            None
        case (e: JsonArray, a: JsonArray) =>
            let expectedItems = e.getItems()
            let actualItems = a.getItems()
            if (expectedItems.size != actualItems.size) {
                return "${path} (${expectedItems.size} items in, ${actualItems.size} out)"
            }
            for (i in 0..expectedItems.size) {
                if (let Some(diff) <- firstDifference(expectedItems[i], actualItems[i], path: "${path}[${i}]")) {
                    return diff
                }
            }
            None
        case (e: JsonString, a: JsonString) where e.getValue() == a.getValue() => None
        case (e: JsonInt, a: JsonInt) where e.getValue() == a.getValue() => None
        case (e: JsonFloat, a: JsonFloat) where e.getValue() == a.getValue() => None
        case (e: JsonBool, a: JsonBool) where e.getValue() == a.getValue() => None
        case (_: JsonNull, _: JsonNull) => None
        case _ => "${path} (value differs)"
    }
}

/**
 * The declarations are plain `@DeriveExt[ToJson, FromJson]`, whose behaviour `stdxx` tests; what is
 * checked here is that they match the document: the real one read and written back loses nothing,
 * and the shapes it happens not to use read too.
 */
@Test
class MetaModelTest {
    @TestCase
    func theShippedMetaModelIsReadAndWrittenLosslessly() {
        // arrange
        let json = String.fromUtf8(File.readFrom("modules/lsp_codegen/metaModel.json"))

        // act
        let rewritten = rewrittenAs<MetaModel>(json)

        // assert
        @Expect("none", firstDifference(treeOf(json), rewritten) ?? "none")
    }

    @TestCase[json in [
        ##"{"kind": "and", "items": [{"kind": "reference", "name": "A"}, {"kind": "reference", "name": "B"}]}"##,
        ##"{"kind": "integerLiteral", "value": -7}"##,
        ##"{"kind": "booleanLiteral", "value": true}"##,
        ##"{"kind": "base", "name": "RegExp"}"##,
        ##"{"kind": "map", "key": {"kind": "base", "name": "URI"}, "value": {"kind": "base", "name": "string"}}"##,
        ##"{"kind": "map", "key": {"kind": "base", "name": "integer"}, "value": {"kind": "base", "name": "string"}}"##
    ]]
    func aTypeTheShippedMetaModelDoesNotUseRoundTrips(json: String) {
        // act
        let rewritten = rewrittenAs<Type>(json)

        // assert
        @Expect("none", firstDifference(treeOf(json), rewritten) ?? "none")
    }

    @TestCase
    func aRequestWithPositionalParamsAndProposedTagsRoundTrips() {
        // arrange
        let json = ##"{"method": "custom/multi", "messageDirection": "both", "result": {"kind": "base", "name": "null"},
            "params": [{"kind": "reference", "name": "A"}, {"kind": "reference", "name": "B"}],
            "proposed": true, "sinceTags": ["3.18.0"], "deprecated": "use something else"}"##

        // act
        let rewritten = rewrittenAs<Request>(json)

        // assert
        @Expect("none", firstDifference(treeOf(json), rewritten) ?? "none")
    }
}
