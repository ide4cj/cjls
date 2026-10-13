package cjls.server

import std.collection.HashMap
import std.env.getTempDirectory
import std.fs.{Directory, exists, File, Path}
import std.time.DateTime
import loupe.vfs.VfsPath
import platform.userCacheDir

let CACHE_NOW = DateTime.ofEpoch(second: 1_800_000_000, nanosecond: 0)

func cacheEnv(vars: Array<(String, String)>): (String) -> ?String {
    let map = HashMap<String, String>(vars)
    {name => map.get(name)}
}

func textOf(path: Path): String {
    String.fromUtf8(File.readFrom(path))
}

func writeText(path: Path, text: String): Unit {
    ensureDir(path.parent)
    File.writeTo(path, text.toArray())
}

@Test
class CacheDirTest {
    @TestCase
    func aProjectsCacheDirectoryIsMadeUnderItsCacheIgnoredAndTagged() {
        // arrange
        let base = Directory.createTemp(getTempDirectory())

        // act
        let cache = CacheDirs(cacheEnv([])).open(VfsPath.file(base)).getOrThrow()

        // assert
        @Expect(cache.path, base.join(".cache").join("cjls"))
        @Expect(textOf(cache.path.join(".gitignore")), "*\n")
        @Expect(textOf(cache.path.join("CACHEDIR.TAG")).startsWith("Signature: 8a477f597d28d172789f06886806bc55"))
        @Expect(textOf(cache.path.join("LAYOUT")), CACHE_LAYOUT)
    }

    @TestCase
    func aDirectoryOfAnotherLayoutIsEmptied() {
        // arrange
        let base = Directory.createTemp(getTempDirectory())
        let dir = base.join(".cache").join("cjls")
        writeText(dir.join("LAYOUT"), "0")
        writeText(dir.join("old").join("file"), "x")
        writeText(dir.join(".gitignore"), "mine\n")

        // act
        let cache = CacheDirs(cacheEnv([])).open(VfsPath.file(base)).getOrThrow()

        // assert
        @Expect(!exists(dir.join("old")))
        @Expect(textOf(cache.path.join(".gitignore")), "*\n")
        @Expect(textOf(cache.path.join("LAYOUT")), CACHE_LAYOUT)
    }

    @TestCase
    func expandedFilesAreRemovedTheFirstTimeAProcessOpensTheDirectoryOnly() {
        // arrange
        let base = Directory.createTemp(getTempDirectory())
        let dirs = CacheDirs(cacheEnv([]))
        let cache = dirs.open(VfsPath.file(base)).getOrThrow()
        let old = cache.path.join(EXPANDED_DIR).join("a.cj.macrocall")
        writeText(old, "old")
        let another = CacheDirs(cacheEnv([]))

        // act
        dirs.open(VfsPath.file(base)).getOrThrow()
        let keptBySameProcess = exists(old)
        another.open(VfsPath.file(base)).getOrThrow()

        // assert
        @Expect(keptBySameProcess)
        @Expect(!exists(old))
    }

    @TestCase
    func aMacroBuildUnusedForAWeekIsRemovedAndOneUsedSinceKept() {
        // arrange
        let base = Directory.createTemp(getTempDirectory())
        let cache = CacheDirs(cacheEnv([])).open(VfsPath.file(base)).getOrThrow()
        let old = cache.macroBuild("1.2.0-cjnative", now: CACHE_NOW - Duration.day * 8)
        writeText(old.join("cjls").join("lib-macro_cjls.macros.so"), "")
        let recent = cache.macroBuild("1.3.0-cjnative", now: CACHE_NOW - Duration.day * 6)

        // act
        CacheDirs(cacheEnv([]), now: {=> CACHE_NOW}).open(VfsPath.file(base)).getOrThrow()

        // assert
        @Expect(!exists(old))
        @Expect(exists(recent))
    }

    @TestCase
    func aMacroBuildLockedByABuildIsKept() {
        // arrange
        let base = Directory.createTemp(getTempDirectory())
        let cache = CacheDirs(cacheEnv([])).open(VfsPath.file(base)).getOrThrow()
        let old = cache.macroBuild("1.2.0-cjnative", now: CACHE_NOW - Duration.day * 8)
        let lock = tryLockCacheDir(old).getOrThrow()

        // act
        try {
            CacheDirs(cacheEnv([]), now: {=> CACHE_NOW}).open(VfsPath.file(base)).getOrThrow()
        } finally {
            lock.close()
        }

        // assert
        @Expect(exists(old.join(USED_FILE)))
    }

    @TestCase
    func aMacroBuildIsNamedByADirectorysNameOnly() {
        // arrange
        let base = Directory.createTemp(getTempDirectory())
        let cache = CacheDirs(cacheEnv([])).open(VfsPath.file(base)).getOrThrow()

        // act, assert
        @AssertThrows[IllegalArgumentException](cache.macroBuild("../x"))
        @AssertThrows[IllegalArgumentException](cache.macroBuild(""))
    }

    @TestCase
    func aProjectThatCannotBeWrittenHasItsDirectoryInTheUsersCache() {
        // arrange: a file where the directory would be
        let base = Directory.createTemp(getTempDirectory())
        writeText(base.join(".cache"), "")
        let user = Directory.createTemp(getTempDirectory())
        let env = cacheEnv([("XDG_CACHE_HOME", user.toString()), ("HOME", user.toString()),
            ("LOCALAPPDATA", user.toString())])
        let project = VfsPath.file(base)

        // act
        let cache = CacheDirs(env).open(project).getOrThrow()

        // assert
        @Expect(cache.path.parent, userCacheDir(env).getOrThrow().join("cjls"))
        @Expect(cache.path.fileName, userCacheEntryOf(project))
        @Expect(textOf(cache.path.join("LAYOUT")), CACHE_LAYOUT)
        let source = project.join("src").join("a.cj")
        let expanded = cache.expandedFileOf(source).getOrThrow()
        @Expect(sourceOfExpanded(expanded), Some(source))
    }

    @TestCase
    func anExpandedFileIsItsSourcesPathUnderExpanded() {
        // arrange
        let base = Directory.createTemp(getTempDirectory())
        let project = VfsPath.file(base)
        let cache = CacheDirs(cacheEnv([])).open(project).getOrThrow()
        let source = project.join("src").join("a").join("b.cj")

        // act
        let expanded = cache.expandedFileOf(source).getOrThrow()

        // assert
        @Expect(expanded, VfsPath.file(base.join(".cache").join("cjls").join("expanded").join("src").join("a").join(
            "b.cj.macrocall")))
        @Expect(sourceOfExpanded(expanded), Some(source))
        @Expect(cache.expandedFileOf(VfsPath.file(base.parent.join("elsewhere.cj"))), None<VfsPath>)
    }

    @TestCase
    func aMacrocallOutsideACacheDirectoryIsNoExpandedFile() {
        // arrange
        let base = VfsPath.file(Directory.createTemp(getTempDirectory()))

        // act, assert
        @Expect(!isExpandedFile(base.join("expanded").join("a.cj.macrocall")))
        @Expect(!isExpandedFile(base.join(".cache").join("cjls").join("expanded").join(".macrocall")))
        @Expect(!isExpandedFile(base.join(".cache").join("cjls").join("expanded").join("a.cj")))
    }
}

@Test
class CacheBaseOfTest {
    @TestCase
    func aFileOfAWorkspaceMemberHasTheWorkspacesDirectory() {
        // arrange
        let root = Directory.createTemp(getTempDirectory())
        writeText(root.join("cjpm.toml"), "[workspace]\nmembers = [\"modules/a\"]\n")
        writeText(root.join("modules").join("a").join("cjpm.toml"), "[package]\nname = \"a\"\n")
        let file = VfsPath.file(root.join("modules").join("a").join("src").join("a.cj"))

        // act
        let base = cacheBaseOf(file, [VfsPath.file(root)], cacheEnv([]))

        // assert
        @Expect(base, Some(VfsPath.file(root)))
    }

    @TestCase
    func aFileOfNoProjectHasTheInnermostRoot() {
        // arrange
        let root = Directory.createTemp(getTempDirectory())
        let inner = VfsPath.file(root).join("inner")
        let file = inner.join("x").join("a.cj")

        // act
        let base = cacheBaseOf(file, [VfsPath.file(root), inner], cacheEnv([]))

        // assert
        @Expect(base, Some(inner))
    }

    @TestCase
    func aFileUnderNoRootHasItsProjectsDirectory() {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        writeText(dir.join("cjpm.toml"), "[package]\nname = \"p\"\n")
        let file = VfsPath.file(dir.join("src").join("a.cj"))

        // act
        let base = cacheBaseOf(file, [], cacheEnv([]))

        // assert
        @Expect(base, Some(VfsPath.file(dir)))
    }

    @TestCase
    func aVirtualFileHasNone() {
        // act, assert
        @Expect(cacheBaseOf(VfsPath.virtual("untitled:1"), [], cacheEnv([])), None<VfsPath>)
    }
}

@Test
class CacheLockTest {
    @TestCase
    func aDirectoryLockedIsNotLockedAgainUntilClosed() {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        let first = tryLockCacheDir(dir).getOrThrow()

        // act
        let whileHeld = tryLockCacheDir(dir)
        first.close()
        let afterwards = tryLockCacheDir(dir)

        // assert
        @Expect(whileHeld.isNone())
        @Expect(afterwards.isSome())
        afterwards?.close()
    }
}
