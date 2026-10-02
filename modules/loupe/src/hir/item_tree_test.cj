package loupe.hir

import std.sync.AtomicInt64
import std.unittest.*
import std.unittest.testmacro.*
import calca.*
import calca.macros.*
import cjsyntax.parse as parseText
import rope.Rope
import loupe.vfs.FileId
import loupe.db.{AnalysisDatabase, SourceFile}

let itemNamesRuns = AtomicInt64(0)

/**
 * A query reading the item tree, as name resolution will; it counts its runs.
 */
@CalcaTracked
func itemNames(db: AnalysisDatabase, file: SourceFile): Array<String> {
    itemNamesRuns.fetchAdd(1)
    itemTree(db, file).items.map {item => String.join(item.names, delimiter: ",")}
}

func treeOf(text: String): ItemTree {
    let parsed = parseText(text)
    ItemTree.of(parsed, AstIdMap.of(parsed))
}

func idsOf(text: String): Array<AstId> {
    treeOf(text).items.map {item => item.id}
}

@Test
class ItemTreeTest {
    @TestCase
    func anEditInsideABodyLeavesTheItemTreeEqualAndWhatReadItAlone() {
        // arrange
        let db = AnalysisDatabase()
        let file = db.setFileText(FileId(0), Rope("func f() {\n    1\n}\nclass C {\n    func m() {}\n}\n"))
        let names = itemNames(db, file)
        let map = astIdMap(db, file)
        let runs = itemNamesRuns.load()

        // act
        db.setFileText(FileId(0), Rope("func f() {\n    let x = 1 + 2\n    x\n}\nclass C {\n    func m() {}\n}\n"))
        let again = itemNames(db, file)
        let movedMap = astIdMap(db, file)

        // assert
        @Expect(again, names)
        @Expect(itemNamesRuns.load() - runs, 0)
        @Expect(movedMap != map, true)
    }

    @TestCase
    func aBlankLineAboveLeavesTheItemTreeEqualAndWhatReadItAlone() {
        // arrange
        let db = AnalysisDatabase()
        let file = db.setFileText(FileId(0), Rope("package p\n\nimport a.b\nfunc f() {}\n"))
        let tree = itemTree(db, file)
        itemNames(db, file)
        let runs = itemNamesRuns.load()

        // act
        db.setFileText(FileId(0), Rope("package p\n\n\nimport a.b\n\n// f\nfunc f() {}\n"))
        let again = itemTree(db, file)
        itemNames(db, file)

        // assert
        @Expect(again, tree)
        @Expect(itemNamesRuns.load() - runs, 0)
    }

    @TestCase
    func anItemAddedOrMovedLeavesTheIdsOfTheOthers() {
        // arrange
        let before = idsOf("func a() {}\nclass C {}\nfunc b() {}\n")

        // act
        let added = idsOf("func z() {}\nfunc a() {}\nclass C {}\nfunc b() {}\n")
        let moved = idsOf("func b() {}\nclass C {}\nfunc a() {}\n")

        // assert
        @Expect(added[1..], before)
        @Expect(moved, [before[2], before[1], before[0]])
    }

    @TestCase
    func overloadsAreToldByTheirOrderAmongTheirName() {
        // arrange
        let text = "func f(x: Int64) {}\nfunc g() {}\nfunc f(x: String) {}\n"

        // act
        let ids = idsOf(text)

        // assert
        @Expect(ids[0].hash, ids[2].hash)
        @Expect(ids[0].index, 0)
        @Expect(ids[2].index, 1)
        @Expect(ids[1].index, 0)
    }

    @TestCase
    func membersAreUnderTheirTypeAndNamedByIt() {
        // arrange
        let text = "class A {\n    func m() {}\n}\nclass B {\n    func m() {}\n}\nenum E {\n    | X | Y(Int64)\n}\n"

        // act
        let items = treeOf(text).items

        // assert
        @Expect(items.map {item => item.kind}, [ItemKind.Class, ItemKind.Class, ItemKind.Enum])
        @Expect(items[0].members[0].names, ["m"])
        @Expect(items[0].members[0].id != items[1].members[0].id, true)
        @Expect(items[2].members.map {item => (item.kind, item.names[0])}.map {it => "${it[0]} ${it[1]}"},
            ["EnumCtor X", "EnumCtor Y"])
    }

    @TestCase
    func anExtendIsNamedByItsTypeAndBoundsAsWrittenWithoutSpaces() {
        // arrange
        let before = idsOf("extend C <: Hashable {}\nextend C <: Equatable<C> {}\n")

        // act
        let after = idsOf("extend   C<:Equatable < C > {}\nextend C <: Hashable {\n    func f() {}\n}\n")

        // assert
        @Expect(before[0] != before[1], true)
        @Expect(before[0].index, 0)
        @Expect(before[1].index, 0)
        @Expect(after, [before[1], before[0]])
    }

    @TestCase
    func aMacroCallOnADeclarationIsThatDeclarationWithTheMacroAndModifiersOfBoth() {
        // arrange
        let text = "@Derive[Equatable]\n@Other\npublic struct S {}\n@M(a b c)\n"

        // act
        let items = treeOf(text).items

        // assert
        @Expect(items.size, 2)
        @Expect(items[0].kind, ItemKind.Struct)
        @Expect(items[0].names, ["S"])
        @Expect(items[0].macros, ["Derive", "Other"])
        @Expect(items[0].has(Modifier.Public), true)
        @Expect(items[1].kind, ItemKind.MacroCall)
        @Expect(items[1].macros, ["M"])
        @Expect(items[1].names.size, 0)
    }

    @TestCase
    func theDeclarationsOfAForeignBlockAreItemsOfItsParent() {
        // arrange
        let text = "foreign {\n    func c(x: Int32): Int32\n    var v: Int32\n}\nfunc f() {}\n"

        // act
        let items = treeOf(text).items

        // assert
        @Expect(items.map {item => item.names[0]}, ["c", "v", "f"])
        @Expect(items[0].has(Modifier.Foreign), true)
        @Expect(items[1].has(Modifier.Foreign), true)
        @Expect(items[2].has(Modifier.Foreign), false)
    }

    @TestCase
    func modifiersAreKeptInOneOrderWhateverTheOrderWritten() {
        // arrange
        let one = treeOf("class C {\n    public static func f() {}\n}\n")

        // act
        let other = treeOf("class C {\n    static public func f() {}\n}\n")

        // assert
        @Expect(one, other)
        @Expect(one.items[0].members[0].modifiers, [Modifier.Static, Modifier.Public])
    }

    @TestCase
    func aLetOfAPatternDeclaresEachOfItsBindings() {
        // arrange
        let text = "let (a, (b, _)) = (1, (2, 3))\nconst K = 1\n"

        // act
        let items = treeOf(text).items

        // assert
        @Expect(items[0].names, ["a", "b"])
        @Expect(items[1].names, ["K"])
        @Expect(items[1].has(Modifier.Const), true)
    }

    @TestCase
    func importsBringOneNameForEachLeafOfTheirBraces() {
        // arrange
        let text = "macro package org::p.q\npublic import a.b.c\nimport a.{b as x, c.*}\nimport org::m.n\n"

        // act
        let tree = treeOf(text)

        // assert
        @Expect(tree.packageHeader, Some(PackageItem("org::p.q", true, [])))
        @Expect(tree.imports.size, 3)
        @Expect(tree.imports[0].modifiers, [Modifier.Public])
        @Expect(tree.imports[0].paths, [ImportPath(["a", "b", "c"])])
        @Expect(tree.imports[1].paths, [ImportPath(["a", "b"], alias: "x"), ImportPath(["a", "c"], isGlob: true)])
        @Expect(tree.imports[2].paths, [ImportPath(["org::m", "n"])])
    }

    @TestCase
    func anIdGoesBackToItsNodeAndTheNodeToItsId() {
        // arrange
        let parsed = parseText("import a.b\nclass C {\n    @M\n    func m() {}\n}\n")
        let map = AstIdMap.of(parsed)
        let tree = ItemTree.of(parsed, map)
        let method = tree.items[0].members[0]

        // act
        let node = map.node(method.id, parsed.syntaxNode()).getOrThrow()
        let importNode = map.node(tree.imports[0].id, parsed.syntaxNode()).getOrThrow()

        // assert
        @Expect(node.text(), "func m() {}")
        @Expect(importNode.text(), "import a.b")
        @Expect(map.all.size, 3)
    }
}
