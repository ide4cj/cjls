package loupe.db

import std.env.getTempDirectory
import std.fs.*
import std.sync.*
import std.time.DateTime
import std.unittest.*
import std.unittest.testmacro.*
import calca.*
import calca.macros.*
import loupe.vfs.*

let binarySizeRuns = AtomicInt64(0)

/**
 * How many bytes the package's `.cjo` holds; it counts its runs.
 */
@CalcaTracked
func binarySize(db: AnalysisDatabase, pkg: BinaryPackageFile): Int64 {
    binarySizeRuns.fetchAdd(1)
    pkg.bytes(db).size
}

let STAMPED = DateTime.now()

/**
 * `std.core` of the binary `std` read as `bytes`, its stamp telling `bytes` and `version` apart.
 */
func coreRead(bytes: ?Array<Byte>, version!: Int64 = 0): CjoFileRead {
    CjoFileRead(CjoFile("std", "std.core", at("std/std.core.cjo")), FileStamp(version, STAMPED), bytes)
}

func binaryPackagesOf(db: AnalysisDatabase): Array<BinaryPackageFile> {
    db.project().getOrThrow().binaryPackages(db)
}

@Test
class BinaryPackageTest {
    @TestCase
    func aBinaryPackageReadIsAnInputOfTheProject() {
        // arrange
        let db = AnalysisDatabase()

        // act
        db.setProject(appProject(), PathInterner(), binaries: [coreRead([1, 2, 3])])

        // assert
        let packages = binaryPackagesOf(db)
        @Expect(packages.map {pkg => pkg.name(db)}, ["std.core"])
        @Expect(packages[0].binary(db), "std")
        @Expect(packages[0].path(db), at("std/std.core.cjo"))
        @Expect(packages[0].bytes(db), [1u8, 2, 3])
        @Expect(db.binaryStamp(coreRead(None).file), Some(FileStamp(0, STAMPED)))
    }

    @TestCase
    func aBinaryPackageLeftUnreadOrReadTheSameChangesNothing() {
        // arrange
        let db = AnalysisDatabase()
        let paths = PathInterner()
        db.setProject(appProject(), paths, binaries: [coreRead([1, 2, 3])])
        let pkg = binaryPackagesOf(db)[0]
        @Expect(binarySize(db, pkg), 3)
        let runs = binarySizeRuns.load()

        // act - unread, then read again as it was, with a new stamp
        db.setProject(appProject(), paths, binaries: [coreRead(None)])
        let unread = binarySize(db, pkg)
        db.setProject(appProject(), paths, binaries: [coreRead([1, 2, 3], version: 1)])
        let same = binarySize(db, pkg)

        // assert
        @Expect(binaryPackagesOf(db), [pkg])
        @Expect(unread, 3)
        @Expect(same, 3)
        @Expect(binarySizeRuns.load() - runs, 0)
        @Expect(db.binaryStamp(coreRead(None).file), Some(FileStamp(1, STAMPED)))
    }

    @TestCase
    func aBinaryPackageReadOtherwiseIsSetAgain() {
        // arrange
        let db = AnalysisDatabase()
        let paths = PathInterner()
        db.setProject(appProject(), paths, binaries: [coreRead([1, 2, 3])])
        let pkg = binaryPackagesOf(db)[0]
        @Expect(binarySize(db, pkg), 3)

        // act
        db.setProject(appProject(), paths, binaries: [coreRead([1, 2, 3, 4], version: 1)])

        // assert
        @Expect(binaryPackagesOf(db), [pkg])
        @Expect(binarySize(db, pkg), 4)
    }

    @TestCase
    func aBinaryPackageGoneHoldsNoBytes() {
        // arrange
        let db = AnalysisDatabase()
        let paths = PathInterner()
        db.setProject(appProject(), paths, binaries: [coreRead([1, 2, 3])])
        let pkg = binaryPackagesOf(db)[0]

        // act
        db.setProject(appProject(), paths)

        // assert
        @Expect(binaryPackagesOf(db).isEmpty())
        @Expect(pkg.bytes(db).isEmpty())
        @Expect(db.binaryStamp(coreRead(None).file), None<FileStamp>)
    }

    @TestCase
    func aBinaryPackageUnreadThatWasNeverReadIsLeftOut() {
        // arrange
        let db = AnalysisDatabase()

        // act
        db.setProject(appProject(), PathInterner(), binaries: [coreRead(None)])

        // assert
        @Expect(binaryPackagesOf(db).isEmpty())
    }

    @TestCase
    func theCjoFilesOfAProjectAreThoseOfItsDirectoriesThenThoseItNames() {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        File.writeTo(dir.join("stdx.b.cjo"), [])
        File.writeTo(dir.join("stdx.a.cjo"), [])
        let named = BinaryPackage("dep.x", at("dep/dep.x.cjo"))
        let model = ProjectModel(Cfg([]), [], binaries: [BinaryModel("stdx", [VfsPath.file(dir)], packages: [named]),
            BinaryModel("dep", [], packages: [named])])

        // act
        let files = model.cjoFiles()
        remove(dir, recursive: true)

        // assert
        @Expect(files.map {file => "${file.binary}:${file.name}"}, ["stdx:stdx.a", "stdx:stdx.b", "stdx:dep.x", "dep:dep.x"])
    }
}
