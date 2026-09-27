package ftoml

import std.collection.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import fjson.*
import fnum.parseFloat64

/*
 * toml-test (in `.corpora/`, at the release `tests/corpora/fetch.py` names):
 * every `valid/` file of a version's list decodes to the tagged JSON beside it, every `invalid/`
 * one is refused with an `FtException` - never another exception.
 */

/** toml-test's `tests/`, where its lists and files are. */
func tomlTest(): Path {
    let suite = Path(".corpora/toml-test")
    if (!exists(suite)) {
        throw IllegalStateException("toml-test is not in .corpora/: run `python3 tests/corpora/fetch.py`")
    }
    suite.join("tests")
}

/** JSON as toml-test writes its expectations, read with `fjson`. */
enum Json {
    | JObject(HashMap<String, Json>)
    | JArray(Array<Json>)
    | JString(String)
    | JOther

    static func read(r: FjReader): Json {
        match (r.peekKind()) {
            case FjKind.JsonObject =>
                let members = HashMap<String, Json>()
                r.beginObject()
                while (r.nextKey()) {
                    let key = r.key()
                    members[key] = read(r)
                }
                JObject(members)
            case FjKind.JsonArray =>
                let items = ArrayList<Json>()
                r.beginArray()
                while (r.nextItem()) {
                    items.add(read(r))
                }
                JArray(items.toArray())
            case FjKind.JsonString => JString(r.readString())
            case _ =>
                r.skipValue()
                JOther
        }
    }
}

/** Where `value` differs from the tagged JSON `expected`, `None` when it does not. */
func differenceOf(value: FtValue, expected: Json, path: String): ?String {
    match ((value.data, expected)) {
        case (AsTable(table), JObject(members)) =>
            if (table.size != members.size) {
                return "${path}: ${table.size} keys, expected ${members.size}"
            }
            for ((key, item) in table) {
                let other = members.get(key) ?? return "${path}: unexpected key `${key}`"
                if (let Some(difference) <- differenceOf(item, other, "${path}.${key}")) {
                    return difference
                }
            }
            None
        case (AsArray(array), JArray(items)) =>
            if (array.size != items.size) {
                return "${path}: ${array.size} items, expected ${items.size}"
            }
            for (i in 0..items.size) {
                if (let Some(difference) <- differenceOf(array[i], items[i], "${path}[${i}]")) {
                    return difference
                }
            }
            None
        case (_, JObject(members)) =>
            match ((members.get("type"), members.get("value"))) {
                case (Some(JString(tag)), Some(JString(text))) =>
                    if (scalarMatches(value.data, tag, text)) {
                        None
                    } else {
                        "${path}: read as ${describe(value.data)}, expected ${tag} ${text}"
                    }
                case _ => "${path}: read as ${value.data.kindName}, expected a table"
            }
        case _ => "${path}: read as ${value.data.kindName}, expected otherwise"
    }
}

func describe(data: FtData): String {
    match (data) {
        case AsString(v) => "string \"${v}\""
        case AsInteger(v) => "integer ${v}"
        case AsFloat(v) => "float ${v}"
        case AsBool(v) => "bool ${v}"
        case AsOffsetDateTime(v) => "datetime ${v}"
        case AsLocalDateTime(v) => "datetime-local ${v}"
        case AsLocalDate(v) => "date-local ${v}"
        case AsLocalTime(v) => "time-local ${v}"
        case _ => data.kindName
    }
}

func scalarMatches(data: FtData, tag: String, text: String): Bool {
    match ((data, tag)) {
        case (AsString(v), "string") => v == text
        case (AsInteger(v), "integer") => v.toString() == text
        case (AsFloat(v), "float") =>
            match (text) {
                case "nan" | "+nan" | "-nan" => v.isNaN()
                case "inf" | "+inf" => v == Float64.Inf
                case "-inf" => v == -Float64.Inf
                case _ => v.toBits() == parseFloat64(text).toBits()
            }
        case (AsBool(v), "bool") => v.toString() == text
        case (AsOffsetDateTime(v), "datetime") => v == OffsetDateTime.parse(text)
        case (AsLocalDateTime(v), "datetime-local") => v == LocalDateTime.parse(text)
        case (AsLocalDate(v), "date-local") => v == LocalDate.parse(text)
        case (AsLocalTime(v), "time-local") => v == LocalTime.parse(text)
        case _ => false
    }
}

/** The files a version's list names, relative to `tests`. */
func listed(tests: Path, version: String): Array<String> {
    let list = String.fromUtf8(File.readFrom(tests.join("files-toml-${version}")))
    list.split("\n").map {line => line.trimAscii()}.filter {line => !line.isEmpty()}
}

/** What is wrong with the `valid/` file `name`, `None` when it reads as its JSON says. */
func validFailure(tests: Path, name: String): ?String {
    let bytes = File.readFrom(tests.join(name))
    let expected = Json.read(FjReader(File.readFrom(tests.join(name.removeSuffix(".toml") + ".json"))))
    try {
        differenceOf(parseToml(bytes).root, expected, name)
    } catch (e: Exception) {
        "${name}: ${e}"
    }
}

/**
 * What is wrong with the `valid/` file `name` written back: the value its JSON describes, through
 * `FtWriter`, has to read as that JSON again - toml-test's encoder cases, with our reader as theirs.
 */
func writtenFailure(tests: Path, name: String): ?String {
    let bytes = File.readFrom(tests.join(name))
    let expected = Json.read(FjReader(File.readFrom(tests.join(name.removeSuffix(".toml") + ".json"))))
    try {
        let written = toTomlBytes(parseToml(bytes).root)
        try {
            differenceOf(parseToml(written).root, expected, name).map {d => "${d}, written as:\n${String.fromUtf8(written)}"}
        } catch (e: Exception) {
            "${name}: ${e}, written as:\n${String.fromUtf8(written)}"
        }
    } catch (e: Exception) {
        "${name}: ${e}"
    }
}

/** What is wrong with the `invalid/` file `name`, `None` when it is refused as it should be. */
func invalidFailure(tests: Path, name: String): ?String {
    let bytes = File.readFrom(tests.join(name))
    try {
        parseToml(bytes)
        "${name}: accepted"
    } catch (_: FtException) {
        None
    } catch (e: Exception) {
        "${name}: refused with ${e}"
    }
}

func failuresOf(tests: Path, names: Array<String>, validOnly: Bool): Array<String> {
    let failures = ArrayList<String>()
    for (name in names where name.endsWith(".toml")) {
        let failure = if (name.startsWith("valid/")) {
            validFailure(tests, name)
        } else if (validOnly) {
            Option<String>.None
        } else {
            invalidFailure(tests, name)
        }
        if (let Some(f) <- failure) {
            failures.add(f)
        }
    }
    failures.toArray()
}

@Test
class TomlTestCorpusTest {
    @TestCase
    func everyFileOfTomlOneOneReadsAsTheSuiteSays() {
        // arrange
        let tests = tomlTest()

        // act
        let failures = failuresOf(tests, listed(tests, "1.1.0"), false)

        // assert
        @Expect(failures, Array<String>())
    }

    @TestCase
    func everyValidFileWrittenBackReadsAsTheSuiteSays() {
        // arrange
        let tests = tomlTest()
        let names = listed(tests, "1.1.0").filter {name => name.startsWith("valid/") && name.endsWith(".toml")}

        // act
        let failures = names |> filterMap {name: String => writtenFailure(tests, name)} |> collectArray

        // assert
        @Expect(failures, Array<String>())
    }

    /** TOML 1.1 reads every valid 1.0 document; some invalid ones it accepts, as inline tables over lines. */
    @TestCase
    func everyValidFileOfTomlOneZeroReadsAsTheSuiteSays() {
        // arrange
        let tests = tomlTest()

        // act
        let failures = failuresOf(tests, listed(tests, "1.0.0"), true)

        // assert
        @Expect(failures, Array<String>())
    }
}
