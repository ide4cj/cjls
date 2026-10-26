package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.fixture.{Fixture, FixtureException, stdCjo, stdCjoRead, stdWithSources}
import loupe.hir.{canonicalDef, DefId, ExtendedType, ItemFile, itemTree, lookUp, memberLookup, Namespace, packageExports,
    packageOfFile, Resolution, resolutionPackage, signatureTypes}
import rope.Rope

/**
 * The loaded attachment, independent of any workspace root or open-document discovery.
 */
func sdkSource(db: AnalysisDatabase, name: String): SourceFile {
    let project = db.project() ?? throw FixtureException("no project for SDK navigation")
    for (source in project.binarySources(db) where source.name == name) {
        return db.sourceFile(source.fileId) ?? throw FixtureException("no source for ${name}")
    }
    throw FixtureException("no attached ${name}")
}

/**
 * Resolves a name identified by its surrounding SDK source text.
 */
func sdkJump(db: AnalysisDatabase, file: SourceFile, context: String, name: String): Array<NavigationTarget> {
    let text = file.text(db).toString()
    let start = text.indexOf(context) ?? throw FixtureException("SDK source has no ${context}")
    let offset = context.indexOf(name) ?? throw FixtureException("${name} absent from ${context}")
    definitionAt(db, file.fileId(db), start + offset)
}

/**
 * Checks a resolved SDK declaration against its source file, name and ranges.
 */
func checkSdkJump(db: AnalysisDatabase, targets: Array<NavigationTarget>, targetFile: String, targetName: String): Unit {
    @Assert(targets.size, 1)
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
        // arrange
        let parsed = Fixture.parse("//- /main.cj module=m package=m\npackage m\nmain() {}")
        let db = parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))],
            models: [stdWithSources(["std.core"])])
        let file = sdkSource(db, "std.core/print.cj")
        let original = file.text(db)
        const MISMATCHED = "package std.core\nfunc fake(value: Int64): Int64 { value }\n"
        let body = MISMATCHED.indexOf("{ value") ?? throw FixtureException("no value in mismatched source")

        // act
        let initial = sdkJump(db, file, "str.rawData()", "rawData")

        // assert
        checkSdkJump(db, initial, "std.core/string.cj", "rawData")

        // act
        db.setFileText(file.fileId(db), Rope(MISMATCHED))
        let context = packageOfFile(db, file)
        let mismatched = definitionAt(db, file.fileId(db), body + 2)

        // assert
        @Expect(context.isNone())
        @Expect(mismatched.isEmpty())

        // act
        db.setFileText(file.fileId(db), original)
        let restored = sdkJump(db, file, "str.rawData()", "rawData")

        // assert
        checkSdkJump(db, restored, "std.core/string.cj", "rawData")
    }

    @TestCase
    func packageDeclarationsPrivateFunctionsParametersLocalsAndMembersResolveInStdBodies() {
        // arrange
        let parsed = Fixture.parse("//- /main.cj module=m package=m\npackage m\nmain() {}")
        let db = parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))],
            models: [stdWithSources(["std.core"])])
        let file = sdkSource(db, "std.core/print.cj")
        let context = packageOfFile(db, file) ?? throw FixtureException("no checked SDK context")

        // act
        let helper = sdkJump(db, file, "let ln = readFromConsole()", "readFromConsole")
        let parameter = sdkJump(db, file, "str.rawData()", "str")
        let local = sdkJump(db, file, "releaseArrayRawData(cp)", "cp")
        let member = sdkJump(db, file, "str.rawData()", "rawData")
        let typeName = sdkJump(db, file, "let build: StringBuilder", "StringBuilder")
        let compilerTypeMember = sdkJump(db, file, "line.isNull()", "isNull")
        let exported = packageExports(db, resolutionPackage(db, context)).names.get("readFromConsole")

        // assert
        checkSdkJump(db, helper, "std.core/print.cj", "readFromConsole")
        checkSdkJump(db, parameter, "std.core/print.cj", "str")
        checkSdkJump(db, local, "std.core/print.cj", "cp")
        checkSdkJump(db, member, "std.core/string.cj", "rawData")
        checkSdkJump(db, typeName, "std.core/string_builder.cj", "StringBuilder")
        checkSdkJump(db, compilerTypeMember, "std.core/c_pointer_resource.cj", "isNull")
        @Expect(exported.isNone())
    }

    @TestCase
    func privateMembersOmittedFromTheBinaryAreOnlyAvailableInsideTheSdkContext() {
        // arrange
        let parsed = Fixture.parse("//- /main.cj module=m package=m\npackage m\nmain() {}")
        let db = parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))],
            models: [stdWithSources(["std.core"])])
        let file = sdkSource(db, "std.core/thread.cj")
        let pkg = packageOfFile(db, file) ?? throw FixtureException("no checked SDK context")
        let thread = match (lookUp(db, pkg, file, "Thread", Namespace.Types)) {
            case Found(ids) => ids[0]
            case _ => throw FixtureException("no Thread")
        }
        let projectFile = db.sourceFile(parsed.files[0].fileId) ?? throw FixtureException("no project source")

        // act
        let helper = sdkJump(db, file, "let rtCJThreadHandle = acquireCJThreadHandle()", "acquireCJThreadHandle")
        let projectMembers = memberLookup(db, [ExtendedType.DeclType(thread)], "acquireCJThreadHandle", from: projectFile)

        // assert
        checkSdkJump(db, helper, "std.core/thread.cj", "acquireCJThreadHandle")
        @Expect(projectMembers.isEmpty())
    }

    @TestCase
    func importsAndMembersOfGenericSelfUseTheInstalledSdkTypes() {
        // arrange
        let names = ["std.core", "std.collection", "std.math"]
        let parsed = Fixture.parse("//- /main.cj module=m package=m\npackage m\nmain() {}")
        let db = parsed.database(binaries: names.map {name => stdCjoRead(name, stdCjo(name))},
            models: [stdWithSources(names)])
        let file = sdkSource(db, "std.collection/array_list.cj")
        let sourceType = itemTree(db, file).items.iterator().filter {one => one.names.contains("ArrayList")}
            .next() ?? throw FixtureException("SDK source has no ArrayList")
        let sourceDef = DefId(db, ItemFile.Source(file), sourceType.id)
        let pkg = packageOfFile(db, file) ?? throw FixtureException("no checked SDK context")

        // act
        let imported = sdkJump(db, file, "sqrt(Float64(span))", "sqrt")
        let member = sdkJump(db, file, "myData.copyTo(newData, 0, 0, newSize)", "copyTo")
        let generic = sdkJump(db, file, "ArrayList<T>(newData)", "T")
        let canonical = canonicalDef(db, sourceDef)
        let resolved = lookUp(db, pkg, file, "ArrayList", Namespace.Types)
        let sourceTy = signatureTypes(db, sourceDef).ty
        let canonicalTy = signatureTypes(db, canonical).ty

        // assert
        checkSdkJump(db, imported, "std.math/math_funcs_cjnative.cj", "sqrt")
        checkSdkJump(db, member, "std.core/array.cj", "copyTo")
        checkSdkJump(db, generic, "std.collection/array_list.cj", "T")
        // A source self type must be the same declaration as binary signatures and imports name.
        @Expect(resolved, Resolution.Found([canonical]))
        @Expect(canonical != sourceDef)
        @Expect(sourceTy, canonicalTy)
    }
}
