package loupe.hir

import std.collection.{ArrayList, HashSet}
import std.env.{getTempDirectory, getVariable}
import std.fs.*
import std.time.DateTime
import std.unittest.*
import std.unittest.testmacro.*
import cjo.openCjo
import rope.Rope
import loupe.vfs.{CjoFile, CjoFileRead, FileId, FileStamp, PathInterner, VfsPath}
import loupe.db.{AnalysisDatabase, BinaryPackageFile, Cfg, ProjectModel}

/**
 * The bytes of `<name>.cjo` of the SDK's std, of whichever target it has first.
 */
func stdCjo(name: String): Array<Byte> {
    let home = Path(getVariable("CANGJIE_HOME") ?? throw IllegalStateException("CANGJIE_HOME names no SDK"))
    for (target in Directory.readFrom(home.join("modules")) where target.isDirectory()) {
        let file = target.path.join("std").join("${name}.cjo")
        if (exists(file)) {
            return File.readFrom(file)
        }
    }
    throw IllegalStateException("no ${name}.cjo under ${home.join("modules")}")
}

/**
 * The input of the package `name` of `std`, holding `bytes`, in `db`.
 */
func binaryPackage(db: AnalysisDatabase, name: String, bytes: Array<Byte>): BinaryPackageFile {
    let file = CjoFile("std", name, VfsPath.file(getTempDirectory().join("${name}.cjo")))
    db.setProject(ProjectModel(Cfg([]), []), PathInterner(),
        binaries: [CjoFileRead(file, FileStamp(bytes.size, DateTime.now()), bytes)])
    db.project().getOrThrow().binaryPackages(db)[0]
}

/**
 * The index of the file `path` among those of the `.cjo` `bytes` hold.
 */
func fileIndex(bytes: Array<Byte>, path: String): Int64 {
    let files = openCjo(bytes).allFiles.toArray()
    for (i in 0..files.size where files[i] == path) {
        return i
    }
    throw IllegalStateException("no file ${path}")
}

func named(items: Array<Item>, name: String): Item {
    for (item in items where item.names == [name]) {
        return item
    }
    throw IllegalStateException("no item ${name}")
}

/**
 * Every item of `trees`, members after their type.
 */
func everyItem(trees: Array<ItemTree>): Array<Item> {
    let all = ArrayList<Item>()
    func add(items: Array<Item>): Unit {
        for (item in items) {
            all.add(item)
            add(item.members)
        }
    }
    for (tree in trees) {
        add(tree.items)
    }
    all.toArray()
}

@Test
class BinaryItemTreeTest {
    @TestCase
    func aTypeOfABinaryPackageIsAnItemOfTheFileItBeganIn() {
        // arrange
        let db = AnalysisDatabase()
        let bytes = stdCjo("std.core")
        let pkg = binaryPackage(db, "std.core", bytes)

        // act
        let trees = binaryItemTrees(db, pkg)

        // assert
        @Expect(trees.size, openCjo(bytes).allFiles.size)
        let tree = trees[fileIndex(bytes, "std.core/string.cj")]
        @Expect(tree.packageHeader, Some(PackageItem("std.core", false, [Modifier.Public])))
        let string = named(tree.items, "String")
        @Expect(string.kind, ItemKind.Struct)
        @Expect(string.modifiers, [Modifier.Public])
        @Expect(string.macros.isEmpty())
    }

    @TestCase
    func theMembersOfATypeAreItsItemsAndOverloadsAreToldApart() {
        // arrange
        let db = AnalysisDatabase()
        let bytes = stdCjo("std.core")
        let pkg = binaryPackage(db, "std.core", bytes)

        // act
        let string = named(binaryItemTrees(db, pkg)[fileIndex(bytes, "std.core/string.cj")].items, "String")

        // assert
        let inits = string.members.filter {member => member.kind == ItemKind.Init}
        @Expect(inits.size > 1)
        @Expect(inits.map {it => it.names}, Array(inits.size) {_ => ["init"]})
        @Expect(inits.map {it => it.id.index}, Array(inits.size) {i => i})
        @Expect(named(string.members, "size").kind, ItemKind.Prop)
        @Expect(named(string.members, "empty").modifiers, [Modifier.Static, Modifier.Public, Modifier.Const])
        let indexOf = string.members.filter {member => member.names == ["indexOf"]}
        @Expect(indexOf.map {it => it.id.index}, Array(indexOf.size) {i => i})
        @Expect(named(string.members, "fromUtf8Unchecked").modifiers, [Modifier.Static, Modifier.Public, Modifier.Unsafe])
    }

    @TestCase
    func enumConstructorsAndBuiltInTypesAreItemsOfTheirOwnKinds() {
        // arrange
        let db = AnalysisDatabase()
        let pkg = binaryPackage(db, "std.core", stdCjo("std.core"))

        // act
        let items = everyItem(binaryItemTrees(db, pkg))

        // assert
        let option = named(items, "Option")
        @Expect(named(option.members, "Some").kind, ItemKind.EnumCtor)
        @Expect(named(option.members, "None").kind, ItemKind.EnumCtor)
        @Expect(named(items, "CPointer").kind, ItemKind.BuiltIn)
        @Expect(named(items, "Byte").kind, ItemKind.TypeAlias)
        @Expect(items.filter {item => item.kind == ItemKind.Extend}.iterator().all {item => item.names.isEmpty()})
    }

    @TestCase
    func whatTheCompilerAddedIsLeftOutButAPrimaryInitAndItsMemberParameters() {
        // arrange
        let db = AnalysisDatabase()
        let pkg = binaryPackage(db, "std.deriving.api", stdCjo("std.deriving.api"))

        // act
        let items = everyItem(binaryItemTrees(db, pkg))

        // assert
        let withPrimary = items.filter {item => item.members.iterator().any {member => member.kind == ItemKind.PrimaryInit}}
        @Expect(!withPrimary.isEmpty())
        for (item in withPrimary) {
            let primary = item.members.filter {member => member.kind == ItemKind.PrimaryInit}
            @Expect(primary[0].names, item.names)
        }
        @Expect(items.iterator().all {item => item.names.iterator().all {name => !name.startsWith("$")}})
    }

    @TestCase
    func aMacroOfAMacroPackageIsAnItemAndWhatCallsItIsNot() {
        // arrange
        let db = AnalysisDatabase()
        let pkg = binaryPackage(db, "std.deriving", stdCjo("std.deriving"))

        // act
        let trees = binaryItemTrees(db, pkg)
        let items = everyItem(trees)

        // assert
        @Expect(trees[0].packageHeader?.isMacro, Some(true))
        @Expect(named(items, "Derive").kind, ItemKind.Macro)
        @Expect(items.iterator().all {item => item.names.iterator().all {name => !name.startsWith("macroCall_")}})
    }

    @TestCase
    func aReExportIsAnImportOfItsFile() {
        // arrange
        let db = AnalysisDatabase()
        let pkg = binaryPackage(db, "std.unittest", stdCjo("std.unittest"))

        // act
        let imports = binaryItemTrees(db, pkg).map {tree => tree.imports}.flatMap {it => it}

        // assert
        let arbitrary = imports.filter {it => it.paths[0].segments == ["std", "unittest", "prop_test", "Arbitrary"]}
        @Expect(arbitrary.size, 1)
        @Expect(arbitrary[0].modifiers, [Modifier.Public])
        @Expect(arbitrary[0].paths[0].alias, None<String>)
        @Expect(!arbitrary[0].paths[0].isGlob)
    }

    @TestCase
    func anExportIdLeadsToItsItemAndItsItemToItsDecl() {
        // arrange
        let db = AnalysisDatabase()
        let bytes = stdCjo("std.core")
        let pkg = binaryPackage(db, "std.core", bytes)

        // act
        let item = binaryExports(db, pkg).itemOf("_CNat6StringE").getOrThrow()
        let decl = binaryDecl(db, pkg, item).getOrThrow()

        // assert
        @Expect(item.file, fileIndex(bytes, "std.core/string.cj"))
        @Expect(named(binaryItemTrees(db, pkg)[item.file].items, "String").id, item.id)
        @Expect(decl.identifier, Some("String"))
        @Expect(binaryExports(db, pkg).itemOf("_CNat9NoSuchOneE"), None<BinaryItem>)
    }

    @TestCase
    func aPackageThatCannotBeReadHasNoItems() {
        // arrange
        let db = AnalysisDatabase()
        let pkg = binaryPackage(db, "std.core", "not a cjo".toArray())

        // act, assert
        @Expect(binaryItemTrees(db, pkg).isEmpty())
        @Expect(binaryExports(db, pkg).itemOf("_CNat6StringE"), None<BinaryItem>)
        @Expect(itemTreeOf(db, ItemFile.Binary(pkg, 0)), ItemTree(None, [], []))
    }

    @TestCase
    func theTreeOfAnItemFileIsThatOfItsSourceOrOfItsFileInItsPackage() {
        // arrange
        let db = AnalysisDatabase()
        let bytes = stdCjo("std.core")
        let pkg = binaryPackage(db, "std.core", bytes)
        let source = db.setFileText(FileId(0), Rope("func f() {}\n"))
        let index = fileIndex(bytes, "std.core/string.cj")

        // act
        let binary = itemTreeOf(db, ItemFile.Binary(pkg, index))
        let text = itemTreeOf(db, ItemFile.Source(source))

        // assert
        @Expect(binary, binaryItemTrees(db, pkg)[index])
        @Expect(text, itemTree(db, source))
        @Expect(ItemFile.Binary(pkg, index) == ItemFile.Binary(pkg, index))
        @Expect(ItemFile.Binary(pkg, index) != ItemFile.Binary(pkg, index + 1))
        @Expect(ItemFile.Source(source) != ItemFile.Binary(pkg, 0))
    }
}

@Test
class BinaryExportIdTest {
    @TestCase
    func anExportIdIsUniqueInItsPackage() {
        // arrange
        let home = Path(getVariable("CANGJIE_HOME") ?? throw IllegalStateException("CANGJIE_HOME names no SDK"))
        let std = Directory.readFrom(home.join("modules")).filter {target => target.isDirectory()}[0].path.join("std")
        let files = Directory.readFrom(std).filter {entry => entry.name.endsWith(".cjo")}

        // act
        let duplicates = ArrayList<String>()
        for (file in files) {
            let seen = HashSet<String>()
            for (decl in openCjo(File.readFrom(file.path)).allDecls) {
                let exportId = decl.exportId ?? ""
                if (!exportId.isEmpty() && !seen.add(exportId)) {
                    duplicates.add("${file.name}: ${exportId}")
                }
            }
        }

        // assert
        @Expect(files.size > 0)
        @Expect(duplicates.toArray(), Array<String>())
    }
}

@Test
class ImportSegmentsTest {
    @TestCase
    func anOrganizationIsOneSegmentWithTheNameAfterIt() {
        // act, assert
        @Expect(importSegments(["org"], "a", true), ["org::a"])
        @Expect(importSegments(["org", "a"], "B", true), ["org::a", "B"])
        @Expect(importSegments(["org", "a"], "*", true), ["org::a"])
        @Expect(importSegments(["org", "a", "b"], "C", true), ["org::a", "b", "C"])
    }

    @TestCase
    func aPathWithNoOrganizationIsItsNamesAndAGlobIsNoSegment() {
        // act, assert
        @Expect(importSegments([], "a", false), ["a"])
        @Expect(importSegments(["a", "b"], "C", false), ["a", "b", "C"])
        @Expect(importSegments(["a", "b"], "*", false), ["a", "b"])
    }
}
