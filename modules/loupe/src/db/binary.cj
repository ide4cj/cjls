package loupe.db

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import cjo.{CjoException, CjoVersionException, openCjo}
import loupe.vfs.*

/**
 * A package of a binary the project may import: the `.cjo` at `path`, a package of the module
 * `module` named `name`, as the file's name gives it (`std.core.cjo`).
 */
@Derive[Equatable]
public struct BinaryPackageModel {
    public BinaryPackageModel(public let module: String, public let name: String, public let path: VfsPath) {}

    /**
     * How rarely it changes: `std`'s with the SDK, any other with the manifest.
     */
    public prop durability: Durability {
        get() {
            if (module == "std") {
                Durability.High
            } else {
                Durability.Medium
            }
        }
    }
}

/**
 * A package compiled already, as the analysis sees it: the bytes of its `.cjo`, read when the
 * project is loaded. One per module and name, never dropped: a package gone is no longer in
 * `BinaryPackages`. Not a file of `Vfs`: a `.cjo` is never opened, edited or parsed as text.
 */
@CalcaInput
public struct BinaryPackageFile {
    public let module: String
    public let name: String
    public var path: VfsPath
    public var bytes: Array<Byte>
}

/**
 * The binary packages the project may import, `std`'s first: at most one per database, set with
 * `High` durability, for it changes with the SDK or a manifest.
 */
@CalcaInput[singleton]
public struct BinaryPackages {
    public var packages: Array<BinaryPackageFile>
}

/**
 * A package `setBinaryPackages` left out, and why.
 */
public struct BinaryProblem {
    public BinaryProblem(
        public let pkg: BinaryPackageModel,
        public let message: String,
        /**
         * The major of the format its file is of, when it is a `.cjo` of another than the one read.
         */
        public let major!: ?UInt8 = None,
        /**
         * Whether it has no `.cjo` of any format, written by a compiler older than format versions.
         */
        public let unversioned!: Bool = false
    ) {}
}

/**
 * The inputs of the binary packages made so far, by module and name, with the path each was last
 * set from; and the stamp of each file as it was last read. Used on the root handle alone.
 */
class Binaries {
    var packages: ?(BinaryPackages, Array<BinaryPackageFile>) = None
    let byKey = HashMap<BinaryKey, (BinaryPackageFile, VfsPath)>()
    let fromPath = HashMap<VfsPath, (FileStamp, BinaryPackageFile)>()
}

/**
 * A binary package by its module and its name.
 */
@Derive[Hashable, Equatable]
struct BinaryKey {
    BinaryKey(let module: String, let name: String) {}
}

extend AnalysisDatabase {
    /**
     * The binary packages, `None` until they are set.
     */
    public func binaryPackages(): ?BinaryPackages {
        BinaryPackages.tryGet(this)
    }

    /**
     * The stamp of the file at `path` as a package was last set from it, `None` if none was: what
     * `readBinaries` need not read again.
     */
    public func binaryStamp(path: VfsPath): ?FileStamp {
        binaries.fromPath.get(path).map {it => it[0]}
    }

    /**
     * Sets the binary packages to those of `packages` `read` has, in one revision, each with its
     * durability: a package is the input of its module and its name, made the first time, and its
     * bytes are set again only when they differ. A package `read` has not is left out, and so is one
     * whose bytes are no `.cjo` of the format `cjo` reads: those are the problems.
     *
     * @throws IllegalStateException - if this is a snapshot, or a query is running on it
     */
    public func setBinaryPackages(packages: Array<BinaryPackageModel>, read: Array<BinaryRead>): Array<BinaryProblem> {
        let byPath = HashMap<VfsPath, BinaryRead>()
        for (file in read) {
            byPath.add(file.path, file)
        }
        let problems = ArrayList<BinaryProblem>()
        // what each package is set to, its bytes `None` where they are what its input holds; read before
        // the batch, since nothing is read inside one
        let wanted = ArrayList<(BinaryPackageModel, BinaryRead, ?Array<Byte>)>()
        for (pkg in packages) {
            let file = byPath.get(pkg.path) ?? continue
            let existing = binaries.byKey.get(BinaryKey(pkg.module, pkg.name))
            let bytes = match (file.bytes) {
                case Some(bytes) =>
                    if (let Some(problem) <- headerProblem(pkg, bytes)) {
                        problems.add(problem)
                        continue
                    }
                    bytes
                case None => match (existing) {
                    case Some((_, path)) where path == pkg.path =>
                        wanted.add((pkg, file, None))
                        continue
                    // unchanged, but last set as another package
                    case _ => (binaries.fromPath.get(pkg.path) ?? continue)[1].bytes(this)
                }
            }
            let same = match (existing) {
                case Some((input, _)) => input.bytes(this) == bytes
                case None => false
            }
            wanted.add((pkg, file, if (same) {
                None
            } else {
                bytes
            }))
        }
        batch {
            let inputs = wanted.toArray().map {wanted => setBinaryPackage(wanted[0], wanted[1], wanted[2])}
            match (binaries.packages) {
                case None => binaries.packages = (BinaryPackages(this, inputs, durability: Durability.High), inputs)
                case Some((singleton, old)) =>
                    if (old != inputs) {
                        singleton.setPackages(this).withDurability(Durability.High).to(inputs)
                    }
                    binaries.packages = (singleton, inputs)
            }
        }
        problems.toArray()
    }

    private func setBinaryPackage(pkg: BinaryPackageModel, file: BinaryRead, bytes: ?Array<Byte>): BinaryPackageFile {
        let key = BinaryKey(pkg.module, pkg.name)
        let durability = pkg.durability
        let input = match (binaries.byKey.get(key)) {
            case Some((input, path)) =>
                if (path != pkg.path) {
                    input.setPath(this).withDurability(durability).to(pkg.path)
                }
                if (let Some(bytes) <- bytes) {
                    input.setBytes(this).withDurability(durability).to(bytes)
                }
                input
            // a package not set yet has bytes to set
            case None => BinaryPackageFile(this, pkg.module, pkg.name, pkg.path, bytes.getOrThrow(),
                durability: durability)
        }
        binaries.byKey.add(key, (input, pkg.path))
        binaries.fromPath.add(pkg.path, (file.stamp, input))
        input
    }
}

/**
 * Why `bytes` are not read as the package `pkg`, `None` if they are a `.cjo` of the format `cjo`
 * reads.
 */
func headerProblem(pkg: BinaryPackageModel, bytes: Array<Byte>): ?BinaryProblem {
    try {
        openCjo(bytes)
        None
    } catch (e: CjoVersionException) {
        BinaryProblem(pkg, "${pkg.path}: ${e.message}", major: e.major, unversioned: e.major.isNone())
    } catch (e: CjoException) {
        BinaryProblem(pkg, "${pkg.path}: ${e.message}")
    }
}
