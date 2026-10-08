package cjls.server

import std.env.getTempDirectory
import std.unittest.*
import std.unittest.testmacro.*
import rope.Rope
import loupe.vfs.VfsPath

func pathOf(name: String): VfsPath {
    VfsPath.file(getTempDirectory().join(name))
}

@Test
class LoadStateTest {
    @TestCase
    func aFileSetDuringALoadIsNotUndoneByWhatTheLoadRead() {
        // arrange
        let state = ServerState()
        let changed = pathOf("changed.cj")
        let deleted = pathOf("deleted.cj")
        let load = state.beginLoad()
        state.setFilesContents([(changed, Some(Rope("newer"))), (deleted, None)])

        // act
        let current = state.setLoadedFiles(load, [(changed, Rope("read before")), (deleted, Rope("read before"))])

        // assert
        @Expect(current)
        @Expect(state.fileContents(changed)?.toString(), Some("newer"))
        @Expect(state.fileContents(deleted).isNone())
    }

    @TestCase
    func anOpenDocumentKeepsTheEditorsTextAgainstALoad() {
        // arrange
        let state = ServerState()
        let path = pathOf("open.cj")
        let load = state.beginLoad()
        state.openDocuments[path] = 1

        // act
        state.setLoadedFiles(load, [(path, Rope("on disk"))])

        // assert
        @Expect(state.knows(path), false)
    }

    @TestCase
    func aLoadBegunEndsTheOneBefore() {
        // arrange
        let state = ServerState()
        let path = pathOf("a.cj")
        let first = state.beginLoad()
        let second = state.beginLoad()

        // act
        let firstSet = state.setLoadedFiles(first, [(path, Rope("first"))])
        let firstEnded = state.endLoad(first)

        // assert
        @Expect(firstSet, false)
        @Expect(firstEnded, false)
        @Expect(state.knows(path), false)
        @Expect(state.isLoading(second))
    }

    @TestCase
    func aLoadEndedSetsNothingMoreAndFilesSetAfterAreNotRemembered() {
        // arrange
        let state = ServerState()
        let path = pathOf("a.cj")
        let load = state.beginLoad()
        state.setLoadedFiles(load, [(path, Rope("read"))])

        // act
        let ended = state.endLoad(load)
        let setAfter = state.setLoadedFiles(load, [(path, Rope("late"))])

        // assert
        @Expect(ended)
        @Expect(setAfter, false)
        @Expect(state.isLoading(load), false)
        @Expect(state.fileContents(path)?.toString(), Some("read"))
    }
}
