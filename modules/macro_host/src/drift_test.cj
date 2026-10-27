package macro_host

import std.collection.*
import std.sort.sort
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import cjsyntax.SyntaxKind
import cjsyntax.ast.Decl
import cjsyntax.parse as parseCangjie
import ginkgo.SyntaxNode
import loupe.db.*
import loupe.fixture.*
import loupe.hir.{
    expandedCalls,
    ItemId,
    itemTree,
    macroExpansion,
    pendingMacroRequests,
    setMacroOutputsByKey
}

/**
 * Every case of std's macros cjls expands itself (#175), in one file.
 */
const STD_MACRO_CASES =
    #"
    //- /main.cj module=m package=m
    package m
    import std.deriving.*
    import std.unittest.*
    import std.unittest.testmacro.*

    @Derive[Equatable, Hashable, ToString, Comparable]
    struct P {
        let x: Int64 = 1
    }

    @Derive[Equatable, Hashable]
    enum E {
        | A
        | B(Int64)
    }

    @Derive[Equatable, Hashable, ToString]
    class G<T> {
        let t: T
        init(t: T) {
            this.t = t
        }
    }

    @Derive[Equatable where T <: Hashable]
    struct W<T> {
        let t: T
        init(t: T) {
            this.t = t
        }
    }

    @Derive[Arbitrary, Shrink]
    struct Q {
        let x: Int64 = 1
    }

    @Test
    class Cases {
        @TestCase
        func one(): Unit {}
    }

    @Test
    func alone(): Unit {}
    "#

/**
 * The modifiers a header may start with, which std and cjls write in orders of their own.
 */
let MODIFIERS =
    [
        "public",
        "private",
        "protected",
        "internal",
        "static",
        "open",
        "override",
        "redef",
        "abstract",
        "sealed",
        "operator",
        "unsafe",
        "mut",
        "const"
    ]

/**
 * Where cjls's own expansion is known to differ from std's in what it declares, each with why; one that no longer
 * differs fails, so the list only shrinks. `@Test` rewrites its class (`class C <: TestClass`, `override` members,
 * a registration in `extend TestPackage`), which an expansion added after the item cannot: cjls declares the
 * supertype and the members in an `extend` of its own (#175).
 */
let KNOWN_DIFFERENCES =
    [
        "Cases: extendCases<:TestClass",
        "Cases: publicfuncasTestSuite():TestSuite",
        "Cases: publicfuncregisterCases():Unit",
        "alone: publicfuncasTestSuite():TestSuite",
        "alone: publicfuncregisterTestCase_alone():Unit"
    ]

/**
 * What `text` declares: the header of each declaration up to its body, and of the members of each type and `extend`
 * in it; its annotations left out, its modifiers in one order, its whitespace gone.
 */
func headersOf(text: String): Array<String> {
    let found = ArrayList<String>()
    addHeaders(parseCangjie(text).syntaxNode(), found)
    found.toArray()
}

func addHeaders(node: SyntaxNode<SyntaxKind>, found: ArrayList<String>): Unit {
    for (child in node.children() where Decl.cast(child).isSome()) {
        let body =
            child
                .children()
                .filter {
                    one =>
                    match (one.kind) {
                        case SyntaxKind.DeclBody |
                            SyntaxKind.EnumBody |
                            SyntaxKind.Block |
                            SyntaxKind.PropBody => true
                        case _ => false
                    }
                }
                .next()
        let end = (body?.textRange.start ?? child.textRange.end) - child.textRange.start
        found.add(normalized(child.text()[..end]))
        if (
            let Some(members) <- body &&
                (members.kind == SyntaxKind.DeclBody || members.kind == SyntaxKind.EnumBody)
        ) {
            addHeaders(members, found)
        }
    }
}

/**
 * `header` without its annotations (`@Attribute[...]`), its leading modifiers sorted, its whitespace gone.
 */
func normalized(header: String): String {
    var rest = header.replace("\n", " ").trimAscii()
    while (rest.startsWith("@")) {
        let close = rest.indexOf("]") ?? break
        rest = rest[close + 1..].trimAscii()
    }
    let words = rest.split(" ", removeEmpty: true)
    var at = 0
    while (at < words.size && MODIFIERS.contains(words[at])) {
        at++
    }
    let modifiers = words[..at].clone()
    sort(modifiers)
    String.join(modifiers.concat(words[at..]), delimiter: "")
}

/**
 * The name of the top-level item `item` of `file`.
 */
func itemNameOf(db: AnalysisDatabase, file: SourceFile, item: ItemId): String {
    for (one in itemTree(db, file).items where one.id == item) {
        return one.names.get(0) ?? ""
    }
    ""
}

/**
 * cjls's own expansions of std's macros (#175) against what the SDK's std generates (#176's step 5): what cjls
 * declares for a call is declared with the same header by the real output, but where `KNOWN_DIFFERENCES` says. A
 * nightly whose std generates otherwise fails it, and shows where cjls's expander is behind.
 */
@Test
class StdExpansionDriftTest {
    @TestCase
    func whatCjlsDeclaresForStdsMacrosTheSdksStdDeclaresToo() {
        // arrange
        let parsed = Fixture.parse(STD_MACRO_CASES)
        let db =
            parsed
                .database(
                    binaries: ["std.core", "std.deriving", "std.unittest", "std.unittest.testmacro"]
                        .map { name => stdCjoRead(name, stdCjo(name)) }
                )
        let file = db.sourceFile(parsed.file("/main.cj").fileId).getOrThrow()
        let own = ArrayList<(ItemId, String)>()
        for (call in expandedCalls(db, file)) {
            for (header in headersOf(macroExpansion(db, call).text)) {
                own.add((call.item(db), header))
            }
        }
        let paths = testSdkPaths()
        let servers = MacroServers(paths, Duration.minute, NoopLogger())

        // act
        while (!pendingMacroRequests(db, file).isEmpty()) {
            let requests =
                sendableRequests(
                    db,
                    [file],
                    HashMap<Package, MacroLibrary>(),
                    stdLibrary: {
                        pkg =>
                        paths.stdMacroLibrary(pkg).map { path => path.toString() }
                    }
                )
            setMacroOutputsByKey(db, expandAll(db, requests, testNumbers(), servers))
        }
        servers.close()

        // assert
        let served = HashMap<ItemId, HashSet<String>>()
        for (call in expandedCalls(db, file) where macroExpansion(db, call).replaces) {
            served[call.item(db)] = HashSet<String>(headersOf(macroExpansion(db, call).text))
        }
        let differing = ArrayList<String>()
        for ((item, header) in own where !(served.get(item)?.contains(header) ?? false)) {
            differing.add("${itemNameOf(db, file, item)}: ${header}")
        }
        let known = HashSet<String>(KNOWN_DIFFERENCES)
        @Expect(String.join(differing.toArray().filter {one => !known.contains(one)}, delimiter: "\n"), "")
        let gone = KNOWN_DIFFERENCES.filter { one => !differing.contains(one) }
        @Expect(String.join(gone, delimiter: "\n"), "")
    }
}
