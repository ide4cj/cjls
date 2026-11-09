package project_model

import std.collection.*
import std.deriving.Derive
import ftoml.*
import loupe.vfs.VfsPath
import stdxx.deriving.*

/**
 * What the project needs of a `cjpm.toml`; the rest is skipped.
 */
@DeriveExt[FromToml]
struct Manifest {
    Manifest(
        @Serde[rename: "package"]
        let pkg!: ?ManifestPackage = None,
        let workspace!: ?Workspace = None,
        let ffi!: ?ForeignInterfaces = None,
        let dependencies!: ?HashMap<String, Dependency> = None,
        let replace!: ?HashMap<String, Dependency> = None,
        @Serde[rename: "test-dependencies"]
        let testDependencies!: ?HashMap<String, Dependency> = None,
        @Serde[rename: "script-dependencies"]
        let scriptDependencies!: ?HashMap<String, Dependency> = None,
        let target!: ?HashMap<String, Target> = None,
        @Serde[rename: "source-set"]
        let sourceSets!: ?Array<SourceSet> = None,
        // not `features`: see `SourceSet.featureNames`
        @Serde[rename: "feature"]
        let featureTables!: ?Array<Feature> = None
    ) {}
}

@DeriveExt[FromToml]
struct ManifestPackage {
    ManifestPackage(
        let name!: String,
        let organization!: ?String = None,
        let version!: ?String = None,
        @Serde[rename: "src-dir"]
        let srcDir!: ?String = None,
        @Serde[rename: "always-enabled-features"]
        let alwaysEnabledFeatures!: ?Array<String> = None
    ) {}
}

@DeriveExt[FromToml]
struct Workspace {
    Workspace(let members!: ?Array<String> = None) {}
}

/**
 * A dependency: a version, or a table saying where it is.
 */
@DeriveExt[FromToml]
@Serde[untagged]
enum Dependency {
    | Version(String)
    | Table(DependencyTable)
}

@DeriveExt[FromToml]
struct DependencyTable {
    DependencyTable(
        let path!: ?String = None,
        let git!: ?String = None,
        let branch!: ?String = None,
        let tag!: ?String = None,
        let commitId!: ?String = None,
        let source!: ?String = None,
        let version!: ?String = None,
        let checksum!: ?String = None
    ) {}
}

/**
 * `[target.<triple>]`.
 */
@DeriveExt[FromToml]
struct Target {
    Target(
        let ffi!: ?ForeignInterfaces = None,
        let debug!: ?TargetMode = None,
        let release!: ?TargetMode = None,
        let dependencies!: ?HashMap<String, Dependency> = None,
        @Serde[rename: "test-dependencies"]
        let testDependencies!: ?HashMap<String, Dependency> = None,
        @Serde[rename: "bin-dependencies"]
        let binDependencies!: ?BinDependencies = None
    ) {}
}

@DeriveExt[FromToml]
struct TargetMode {
    TargetMode(
        let ffi!: ?ForeignInterfaces = None,
        let dependencies!: ?HashMap<String, Dependency> = None,
        @Serde[rename: "test-dependencies"]
        let testDependencies!: ?HashMap<String, Dependency> = None,
        @Serde[rename: "bin-dependencies"]
        let binDependencies!: ?BinDependencies = None
    ) {}
}

@DeriveExt[FromToml]
struct BinDependencies {
    BinDependencies(
        @Serde[rename: "path-option"]
        let pathOption!: ?Array<String> = None,
        @Serde[rename: "package-option"]
        let packageOption!: ?HashMap<String, String> = None
    ) {}
}

/**
 * A physical manifest visited within one independent dependency graph.
 */
@Derive[Hashable, Equatable]
struct CjpmDirectory {
    CjpmDirectory(let dir: VfsPath, let isScript!: Bool) {}
}

/**
 * A module name selected within the ordinary or build-script dependency graph.
 */
@Derive[Hashable, Equatable]
struct CjpmSelection {
    CjpmSelection(let name: String, let isScript!: Bool) {}
}

/**
 * Native linker inputs, independent of Cangjie source and binary dependencies.
 */
@DeriveExt[FromToml]
struct ForeignInterfaces {
    ForeignInterfaces(let c!: ?HashMap<String, CLibrary> = None) {}
}

@DeriveExt[FromToml]
struct CLibrary {
    CLibrary(let path!: String = "") {}
}
