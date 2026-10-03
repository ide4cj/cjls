package loupe.db

import std.env.getVariable
import std.fs.*
import std.sync.*
import std.time.DateTime
import std.unittest.*
import std.unittest.testmacro.*
import calca.*
import calca.macros.*
import loupe.vfs.*

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

let binarySizeRuns = AtomicInt64(0)

/**
 * How many bytes the package has; it counts its runs.
 */
@CalcaTracked
func binarySize(db: AnalysisDatabase, pkg: BinaryPackageFile): Int64 {
    binarySizeRuns.fetchAdd(1)
    pkg.bytes(db).size
}

let STAMP = FileStamp(1, DateTime.UnixEpoch)

func readOf(path: VfsPath, bytes: ?Array<Byte>): BinaryRead {
    BinaryRead(path, STAMP, bytes)
}

func namesOf(db: AnalysisDatabase): Array<String> {
    db.binaryPackages().getOrThrow().packages(db).map {pkg => "${pkg.module(db)}:${pkg.name(db)}"}
}

@Test
class BinaryPackagesTest {
    @TestCase
    func thePackagesReadAreSetAsInputsInTheOrderGiven() {
        // arrange
        let db = AnalysisDatabase()
        let core = BinaryPackageModel("std", "std.core", at("sdk/std.core.cjo"))
        let other = BinaryPackageModel("stdx", "stdx.other", at("sdk/stdx.other.cjo"))
        let bytes = stdCjo("std.core")

        // act
        let problems = db.setBinaryPackages([core, other], [readOf(other.path, bytes), readOf(core.path, bytes)])

        // assert
        @Expect(problems.size, 0)
        @Expect(namesOf(db), ["std:std.core", "stdx:stdx.other"])
        @Expect(db.binaryPackages().getOrThrow().packages(db)[0].bytes(db).size, bytes.size)
        @Expect(db.binaryStamp(core.path), Some(STAMP))
        @Expect(core.durability, Durability.High)
        @Expect(other.durability, Durability.Medium)
    }

    @TestCase
    func aFileUnchangedOrOfTheSameBytesKeepsItsInputAndWhatReadIt() {
        // arrange
        let db = AnalysisDatabase()
        let core = BinaryPackageModel("std", "std.core", at("sdk/std.core.cjo"))
        let bytes = stdCjo("std.core")
        db.setBinaryPackages([core], [readOf(core.path, bytes)])
        let input = db.binaryPackages().getOrThrow().packages(db)[0]
        @Expect(binarySize(db, input), bytes.size)
        let runs = binarySizeRuns.load()

        // act
        db.setBinaryPackages([core], [readOf(core.path, None)])
        let unchanged = db.binaryPackages().getOrThrow().packages(db)[0]
        db.setBinaryPackages([core], [readOf(core.path, bytes.clone())])
        let size = binarySize(db, input)

        // assert
        @Expect(unchanged, input)
        @Expect(size, bytes.size)
        @Expect(binarySizeRuns.load() - runs, 0)
    }

    @TestCase
    func otherBytesAreSetOnTheSameInput() {
        // arrange
        let db = AnalysisDatabase()
        let pkg = BinaryPackageModel("std", "std.math", at("sdk/std.math.cjo"))
        db.setBinaryPackages([pkg], [readOf(pkg.path, stdCjo("std.math"))])
        let input = db.binaryPackages().getOrThrow().packages(db)[0]
        let other = stdCjo("std.core")

        // act
        db.setBinaryPackages([pkg], [readOf(pkg.path, other)])

        // assert
        @Expect(db.binaryPackages().getOrThrow().packages(db)[0], input)
        @Expect(binarySize(db, input), other.size)
    }

    @TestCase
    func bytesThatAreNoCjoAreAProblemAndThePackageIsLeftOut() {
        // arrange
        let db = AnalysisDatabase()
        let broken = BinaryPackageModel("std", "std.broken", at("sdk/std.broken.cjo"))
        let core = BinaryPackageModel("std", "std.core", at("sdk/std.core.cjo"))

        // act
        let problems = db.setBinaryPackages([broken, core],
            [readOf(broken.path, "not a cjo".toArray()), readOf(core.path, stdCjo("std.core"))])

        // assert
        @Expect(problems.map {problem => problem.pkg}, [broken])
        @Expect(problems[0].message, "${broken.path}: not a .cjo")
        @Expect(problems[0].major, None<UInt8>)
        @Expect(namesOf(db), ["std:std.core"])
    }

    @TestCase
    func aPackageNotReadIsNoLongerAmongThem() {
        // arrange
        let db = AnalysisDatabase()
        let core = BinaryPackageModel("std", "std.core", at("sdk/std.core.cjo"))
        let math = BinaryPackageModel("std", "std.math", at("sdk/std.math.cjo"))
        db.setBinaryPackages([core, math], [readOf(core.path, stdCjo("std.core")), readOf(math.path, stdCjo("std.math"))])

        // act - over the budget, or gone
        db.setBinaryPackages([core, math], [readOf(core.path, None)])

        // assert
        @Expect(namesOf(db), ["std:std.core"])
    }

    @TestCase
    func aFileUnchangedButLastSetAsAnotherPackageGivesItItsBytes() {
        // arrange
        let db = AnalysisDatabase()
        let path = at("sdk/std.core.cjo")
        let bytes = stdCjo("std.core")
        db.setBinaryPackages([BinaryPackageModel("std", "std.core", path)], [readOf(path, bytes)])

        // act - the same file, now of a binary named otherwise
        db.setBinaryPackages([BinaryPackageModel("sdk", "std.core", path)], [readOf(path, None)])

        // assert
        @Expect(namesOf(db), ["sdk:std.core"])
        @Expect(db.binaryPackages().getOrThrow().packages(db)[0].bytes(db).size, bytes.size)
    }
}
