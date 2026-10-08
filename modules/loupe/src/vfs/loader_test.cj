package loupe.vfs

import std.env.getTempDirectory
import std.fs.*
import std.sort.sort
import std.unittest.*
import std.unittest.testmacro.*
import rope.Rope

/**
 * A directory of its own under the temporary one, holding `files` (paths relative to it, with `/`
 * between names, and their text).
 */
func tree(files: Array<(String, String)>): Path {
    let dir = Directory.createTemp(getTempDirectory())
    for ((relative, text) in files) {
        let path = relative.split("/").fold(dir) {parent, name => parent.join(name)}
        if (!exists(path.parent)) {
            Directory.create(path.parent, recursive: true)
        }
        File.writeTo(path, text.toArray())
    }
    dir
}

/**
 * What `readRoots` read, as `path=text`, the path relative to `dir` with `/` between names; sorted.
 */
func readUnder(dir: Path, roots!: Array<VfsPath> = [VfsPath.file(dir)]): Array<String> {
    let root = VfsPath.file(dir)
    let read = readRoots(roots).files.map {
        file => String.join(file[0].segmentsUnder(root).getOrThrow(), delimiter: "/") + "=" + file[1].toString()
    }
    sort(read)
    read
}

@Test
class LoaderTest {
    @TestCase
    func aRootGivesEveryCangjieFileUnderIt() {
        // arrange
        let dir = tree([("a.cj", "a"), ("src/b.cj", "b"), ("src/deep/c.cj", "c"), ("README.md", "r")])

        // act
        let read = readUnder(dir)
        remove(dir, recursive: true)

        // assert
        @Expect(read, ["a.cj=a", "src/b.cj=b", "src/deep/c.cj=c"])
    }

    @TestCase
    func targetAndHiddenDirectoriesAreLeftOut() {
        // arrange
        let dir = tree([("a.cj", "a"), ("target/release/g.cj", "g"), (".git/h.cj", "h"), ("src/.cache/i.cj", "i")])

        // act
        let read = readUnder(dir)
        remove(dir, recursive: true)

        // assert
        @Expect(read, ["a.cj=a"])
    }

    @TestCase
    func aFileNotUtf8IsLeftOut() {
        // arrange
        let dir = tree([("a.cj", "a")])
        File.writeTo(dir.join("b.cj"), [0xFF, 0xFE, 0x00])

        // act
        let read = readUnder(dir)
        remove(dir, recursive: true)

        // assert
        @Expect(read, ["a.cj=a"])
    }

    @TestCase
    func aFileThatDoesNotFitTheBudgetIsLeftOutAndTheRestRead() {
        // arrange - three files of four bytes, one of twenty
        let dir = tree([("a.cj", "aaaa"), ("big.cj", "bbbbbbbbbbbbbbbbbbbb"), ("c.cj", "cccc"), ("d.cj", "dddd")])

        // act
        let read = readRoots([VfsPath.file(dir)], budget: 10)
        let all = readRoots([VfsPath.file(dir)], budget: 32)
        remove(dir, recursive: true)

        // assert - whichever order the disk lists them in, two small ones fit and the big one never
        @Expect(read.files.size, 2)
        @Expect(read.files.iterator().all {file => file[1].size == 4})
        @Expect(read.truncated)
        @Expect(all.files.size, 4)
        @Expect(!all.truncated)
    }

    @TestCase
    func aRootInsideAnotherIsReadOnce() {
        // arrange
        let dir = tree([("a.cj", "a"), ("sub/b.cj", "b")])
        let roots = [VfsPath.file(dir.join("sub")), VfsPath.file(dir), VfsPath.file(dir)]

        // act
        let read = readUnder(dir, roots: roots)
        remove(dir, recursive: true)

        // assert
        @Expect(read, ["a.cj=a", "sub/b.cj=b"])
    }

    @TestCase
    func aRootNotThereOrVirtualGivesNothing() {
        // act
        let read = readRoots([inTemp("cjls-no-such-directory"), VfsPath.virtual("untitled:Untitled-1")]).files

        // assert
        @Expect(read.size, 0)
    }

    @TestCase
    func aFileOfTheWorkspaceIsOneTheWalkWouldRead() {
        // arrange
        let root = inTemp("ws")
        let other = inTemp("elsewhere")

        // act, assert
        @Expect(isWorkspaceFile(inTemp("ws/src/a.cj"), [other, root]))
        @Expect(!isWorkspaceFile(inTemp("ws/src/a.txt"), [root]))
        @Expect(!isWorkspaceFile(inTemp("ws/target/a.cj"), [root]))
        @Expect(!isWorkspaceFile(inTemp("ws/.git/a.cj"), [root]))
        @Expect(!isWorkspaceFile(inTemp("wsx/a.cj"), [root]))
        @Expect(!isWorkspaceFile(inTemp("elsewhere.cj"), [root]))
        @Expect(!isWorkspaceFile(VfsPath.virtual("untitled:a.cj"), [root]))
    }

    @TestCase
    func aDirectoryOfTheWorkspaceIsOneTheWalkWouldGoInto() {
        // arrange
        let root = inTemp("ws")

        // act, assert
        @Expect(isWorkspaceDirectory(inTemp("ws/src/net"), [root]))
        @Expect(!isWorkspaceDirectory(inTemp("ws"), [root]))
        @Expect(!isWorkspaceDirectory(inTemp("ws/target"), [root]))
        @Expect(!isWorkspaceDirectory(inTemp("ws/target/release"), [root]))
        @Expect(!isWorkspaceDirectory(inTemp("ws/src/.cache"), [root]))
        @Expect(!isWorkspaceDirectory(inTemp("elsewhere/src"), [root]))
    }

    @TestCase
    func aPathIsUnderItselfAndWhatHoldsIt() {
        // arrange
        let dir = inTemp("ws")

        // act, assert
        @Expect(inTemp("ws").isUnder(dir))
        @Expect(inTemp("ws/src/a.cj").isUnder(dir))
        @Expect(!inTemp("wsx/a.cj").isUnder(dir))
        @Expect(!inTemp("a.cj").isUnder(dir))
        @Expect(!VfsPath.virtual("untitled:a").isUnder(dir))
    }

    @TestCase
    func aFileReadFromDiskIsWhatItHolds() {
        // arrange
        let dir = tree([("a.cj", "on disk")])

        // act
        let there = readFile(VfsPath.file(dir.join("a.cj")))
        let missing = readFile(VfsPath.file(dir.join("b.cj")))
        remove(dir, recursive: true)

        // assert
        @Expect(there, Some(Rope("on disk")))
        @Expect(missing, None<Rope>)
    }
}

@When[os != "Windows"]
@Test
class LoaderOnPosixTest {
    @TestCase
    func symbolicLinksAreNotFollowed() {
        // arrange - a link back to the root would make the walk cycle
        let dir = tree([("a.cj", "a")])
        Directory.create(dir.join("sub"))
        SymbolicLink.create(dir.join("sub").join("loop"), to: dir)
        SymbolicLink.create(dir.join("b.cj"), to: dir.join("a.cj"))

        // act
        let read = readUnder(dir)
        remove(dir, recursive: true)

        // assert
        @Expect(read, ["a.cj=a"])
    }

    @TestCase
    func theRootOfTheFileSystemHoldsEveryAbsolutePath() {
        // act, assert
        @Expect(VfsPath.file("/src/a.cj").isUnder(VfsPath.file("/")))
        @Expect(VfsPath.file("/src/a.cj").segmentsUnder(VfsPath.file("/")), Some(["src", "a.cj"]))
    }
}
