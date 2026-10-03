package loupe.hir

import std.env.{getTempDirectory, getVariable}
import std.fs.*
import std.time.DateTime
import std.unittest.*
import std.unittest.testmacro.*
import cjo.openCjo
import rope.Rope
import loupe.vfs.*
import loupe.db.{AnalysisDatabase, BinaryPackageFile, BinaryPackageModel}

/**
 * The bytes of `<name>.cjo` of the SDK's std, of whichever target it has first.
 */
func stdCjo(name: String): Array<Byte> {
    let home = Path(getVariable("CANGJIE_HOME") ?? throw IllegalStateException("CANGJIE_HOME names no SDK, whose std these tests read"))
    for (target in Directory.readFrom(home.join("modules")) where target.isDirectory()) {
        let file = target.path.join("std").join("${name}.cjo")
        if (exists(file)) {
            return File.readFrom(file)
        }
    }
    throw IllegalStateException("no ${name}.cjo under ${home.join("modules")}")
}

/**
 * The input of std's package `name` in `db`, its bytes the SDK's.
 */
func stdPackage(db: AnalysisDatabase, name: String): BinaryPackageFile {
    let pkg = BinaryPackageModel("std", name, VfsPath.file(getTempDirectory().join("sdk").join("${name}.cjo")))
    db.setBinaryPackages([pkg], [BinaryRead(pkg.path, FileStamp(1, DateTime.UnixEpoch), stdCjo(name))])
    db.binaryPackages().getOrThrow().packages(db)[0]
}

/**
 * The index of the file named `file` among `name`'s `allFiles`.
 */
func fileIndex(name: String, file: String): Int64 {
    let files = openCjo(stdCjo(name)).allFiles
    for (i in 0..files.size where files[i] == file) {
        return i
    }
    throw IllegalStateException("${name} has no file ${file}")
}

func itemNamed(items: Array<Item>, name: String): Item {
    for (item in items where item.names.contains(name)) {
        return item
    }
    throw IllegalStateException("no item ${name} among ${items.map {item => item.names}}")
}

func allItems(trees: Array<ItemTree>): Array<Item> {
    trees.map {tree => tree.items}.flatMap {items => items}
}

@Test
class BinaryItemTreeTest {
    @TestCase
    func stringIsAPublicStructInTheTreeOfItsFileWithItsMembers() {
        // arrange
        let db = AnalysisDatabase()
        let core = stdPackage(db, "std.core")

        // act
        let trees = binaryItemTrees(db, core)

        // assert
        let tree = trees[fileIndex("std.core", "std.core/string.cj")]
        @Expect(tree.packageHeader.map {header => header.name}, Some("std.core"))
        let string = itemNamed(tree.items, "String")
        @Expect(string.kind, ItemKind.Struct)
        @Expect(string.has(Modifier.Public))
        @Expect(!string.has(Modifier.Private))
        @Expect(string.members.iterator().any {member => member.kind == ItemKind.Init})
        @Expect(itemNamed(string.members, "size").kind, ItemKind.Prop)
    }

    @TestCase
    func aTypeBuiltIntoTheCompilerIsABuiltInItem() {
        // arrange
        let db = AnalysisDatabase()

        // act
        let items = allItems(binaryItemTrees(db, stdPackage(db, "std.core")))

        // assert
        @Expect(itemNamed(items, "CPointer").kind, ItemKind.BuiltIn)
        @Expect(itemNamed(items, "VArray").kind, ItemKind.BuiltIn)
        // `Array` is a struct of std.core, on the built-in `RawArray`
        @Expect(itemNamed(items, "Array").kind, ItemKind.Struct)
    }

    @TestCase
    func anEnumsConstructorsAreItsMembers() {
        // arrange
        let db = AnalysisDatabase()

        // act
        let option = itemNamed(allItems(binaryItemTrees(db, stdPackage(db, "std.core"))), "Option")

        // assert
        @Expect(option.kind, ItemKind.Enum)
        @Expect(itemNamed(option.members, "Some").kind, ItemKind.EnumCtor)
        @Expect(itemNamed(option.members, "None").kind, ItemKind.EnumCtor)
    }

    @TestCase
    func anExportIdLeadsToItsItemAndBackToItsDecl() {
        // arrange
        let db = AnalysisDatabase()
        let core = stdPackage(db, "std.core")

        // act
        let ref = binaryExports(db, core).get("_CNat6StringE").getOrThrow()

        // assert
        let tree = itemTreeOf(db, ItemFile.Binary(core, ref.file))
        @Expect(tree.items.iterator().filter {item => item.id == ref.id}.next().map {item => item.names}, Some(["String"]))
        @Expect(binaryDecl(db, core, ref).flatMap {decl => decl.identifier}, Some("String"))
        @Expect(binaryExports(db, core).get("_CNat9NoSuchE").isNone())
    }

    @TestCase
    func aReExportIsAPublicImportOfItsFile() {
        // arrange
        let db = AnalysisDatabase()

        // act
        let imports = binaryItemTrees(db, stdPackage(db, "std.unittest")).map {tree => tree.imports}.flatMap {it => it}

        // assert
        let arbitrary = imports.iterator().filter {
            item => item.paths.iterator().any {path => path.segments == ["std", "unittest", "prop_test", "Arbitrary"]}
        }.next().getOrThrow()
        @Expect(arbitrary.modifiers, [Modifier.Public])
        @Expect(arbitrary.id.kind, ItemKind.Import)
    }

    @TestCase
    func whatTheCompilerAddedIsLeftOutButAPrimaryConstructorAndItsFields() {
        // arrange
        let db = AnalysisDatabase()

        // act
        let deriving = allItems(binaryItemTrees(db, stdPackage(db, "std.deriving")))
        let options = itemNamed(allItems(binaryItemTrees(db, stdPackage(db, "std.deriving.impl"))), "InputOptions")

        // assert
        @Expect(itemNamed(deriving, "Derive").kind, ItemKind.Macro)
        @Expect(!deriving.iterator().any {item => item.names.iterator().any {name => name.startsWith("macroCall_")}})
        @Expect(itemNamed(options.members, "InputOptions").kind, ItemKind.PrimaryInit)
        @Expect(itemNamed(options.members, "origin").kind, ItemKind.Var)
    }

    @TestCase
    func theSameBytesAreLoweredToTheSameIds() {
        // arrange
        let bytes = stdCjo("std.collection")

        // act, assert
        @Expect(lowerBinary(bytes) == lowerBinary(bytes.clone()))
    }

    @TestCase
    func bytesThatCannotBeReadHaveNoTreesAndAnIndexOfNoFileAnEmptyOne() {
        // arrange
        let db = AnalysisDatabase()
        let core = stdPackage(db, "std.core")

        // act
        let broken = lowerBinary("not a cjo".toArray())
        let none = itemTreeOf(db, ItemFile.Binary(core, 100000))

        // assert
        @Expect(broken.trees.size, 0)
        @Expect(broken.exports.size, 0)
        @Expect(none, ItemTree(None, [], []))
    }

    @TestCase
    func aSourceFileIsItsOwnTree() {
        // arrange
        let db = AnalysisDatabase()
        let file = db.setFileText(FileId(0), Rope("class C {}\n"))

        // act
        let tree = itemTreeOf(db, ItemFile.Source(file))

        // assert
        @Expect(tree, itemTree(db, file))
        @Expect(ItemFile.Source(file) == ItemFile.Source(file))
        @Expect(ItemFile.Source(file).hashCode(), ItemFile.Source(file).hashCode())
    }
}
