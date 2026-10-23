package loupe

import std.unittest.*
import std.unittest.testmacro.*
import rope.Rope
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.fixture.*
import loupe.hir.*

/** The loaded attachment, independent of any workspace root or open-document discovery. */
func sdkSource(db: AnalysisDatabase, name: String): SourceFile {
    for (source in db.project().getOrThrow().binarySources(db) where source.name == name) {
        return db.sourceFile(source.fileId).getOrThrow()
    }
    throw FixtureException("no attached ${name}")
}

func checkSdkJump(db: AnalysisDatabase, file: SourceFile, context: String, name: String,
    targetFile: String, targetName: String): Unit {
    let text = file.text(db).toString()
    let at = text.indexOf(context).getOrThrow() + context.indexOf(name).getOrThrow()
    let targets = definitionAt(db, file.fileId(db), at)
    @Assert("${context}: ${targets.size}", "${context}: 1")
    let target = targets[0]
    let source = sdkSource(db, targetFile)
    @Expect(target.fileId, source.fileId(db))
    @Expect(source.text(db).slice(target.focusRange.start..target.focusRange.end).toString(), targetName)
    @Expect(target.fullRange.containsRange(target.focusRange))
}

@Test
class DefinitionSdkSourceTest {
    @TestCase
    func replacingAnAttachmentInvalidatesItsContextAndRestoringItRestoresNavigation() {
        let parsed = Fixture.parse("//- /main.cj module=m package=m\npackage m\nmain() {}")
        let db = parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))],
            models: [stdWithSources(["std.core"])])
        let file = sdkSource(db, "std.core/print.cj")
        let original = file.text(db)
        checkSdkJump(db, file, "str.rawData()", "rawData", "std.core/string.cj", "rawData")
        let mismatched = "package std.core\nfunc fake(value: Int64): Int64 { value }\n"
        db.setFileText(file.fileId(db), Rope(mismatched))
        @Expect(packageOfFile(db, file).isNone())
        @Expect(definitionAt(db, file.fileId(db), mismatched.indexOf("{ value").getOrThrow() + 2).isEmpty())
        db.setFileText(file.fileId(db), original)
        checkSdkJump(db, file, "str.rawData()", "rawData", "std.core/string.cj", "rawData")
    }

    @TestCase
    func packageDeclarationsPrivateFunctionsParametersLocalsAndMembersResolveInStdBodies() {
        let parsed = Fixture.parse("//- /main.cj module=m package=m\npackage m\nmain() {}")
        let db = parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))],
            models: [stdWithSources(["std.core"])])
        let file = sdkSource(db, "std.core/print.cj")
        checkSdkJump(db, file, "let ln = readFromConsole()", "readFromConsole", "std.core/print.cj", "readFromConsole")
        checkSdkJump(db, file, "str.rawData()", "str", "std.core/print.cj", "str")
        checkSdkJump(db, file, "releaseArrayRawData(cp)", "cp", "std.core/print.cj", "cp")
        checkSdkJump(db, file, "str.rawData()", "rawData", "std.core/string.cj", "rawData")
        checkSdkJump(db, file, "let build: StringBuilder", "StringBuilder", "std.core/string_builder.cj", "StringBuilder")
        checkSdkJump(db, file, "line.isNull()", "isNull", "std.core/c_pointer_resource.cj", "isNull")
        let context = packageOfFile(db, file).getOrThrow()
        @Expect(packageExports(db, resolutionPackage(db, context)).names.get("readFromConsole").isNone())
    }

    @TestCase
    func privateMembersOmittedFromTheBinaryAreOnlyAvailableInsideTheSdkContext() {
        let parsed = Fixture.parse("//- /main.cj module=m package=m\npackage m\nmain() {}")
        let db = parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))],
            models: [stdWithSources(["std.core"])])
        let file = sdkSource(db, "std.core/thread.cj")
        checkSdkJump(db, file, "let rtCJThreadHandle = acquireCJThreadHandle()", "acquireCJThreadHandle",
            "std.core/thread.cj", "acquireCJThreadHandle")
        let pkg = packageOfFile(db, file).getOrThrow()
        let thread = match (lookUp(db, pkg, file, "Thread", Namespace.Types)) {
            case Found(ids) => ids[0]
            case _ => throw FixtureException("no Thread")
        }
        let projectFile = db.sourceFile(parsed.files[0].fileId).getOrThrow()
        @Expect(memberLookup(db, [ExtendedType.DeclType(thread)], "acquireCJThreadHandle", from: projectFile).isEmpty())
    }

    @TestCase
    func importsAndMembersOfGenericSelfUseTheInstalledSdkTypes() {
        let names = ["std.core", "std.collection", "std.math"]
        let parsed = Fixture.parse("//- /main.cj module=m package=m\npackage m\nmain() {}")
        let db = parsed.database(binaries: names.map {name => stdCjoRead(name, stdCjo(name))},
            models: [stdWithSources(names)])
        let file = sdkSource(db, "std.collection/array_list.cj")
        checkSdkJump(db, file, "sqrt(Float64(span))", "sqrt", "std.math/math_funcs_cjnative.cj", "sqrt")
        checkSdkJump(db, file, "myData.copyTo(newData, 0, 0, newSize)", "copyTo", "std.core/array.cj", "copyTo")
        checkSdkJump(db, file, "ArrayList<T>(newData)", "T", "std.collection/array_list.cj", "T")
        // A source self type must be the same declaration as binary signatures and imports name.
        let sourceType = itemTree(db, file).items.iterator().filter {one => one.names.contains("ArrayList")}.next().getOrThrow()
        let sourceDef = DefId(db, ItemFile.Source(file), sourceType.id)
        let canonical = canonicalDef(db, sourceDef)
        let pkg = packageOfFile(db, file).getOrThrow()
        let resolved = lookUp(db, pkg, file, "ArrayList", Namespace.Types)
        @Expect(resolved, Resolution.Found([canonical]))
        @Expect(canonical != sourceDef)
        @Expect(signatureTypes(db, sourceDef).ty, signatureTypes(db, canonical).ty)
    }
}
