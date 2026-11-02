package cjmcp

import std.collection.ArrayList
import std.collection.concurrent.LinkedBlockingQueue
import std.env.getTempDirectory
import std.fs.*
import std.sync.AtomicBool
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange
import loupe.{expandedMacro, fileStructure, macroCallAt}
import loupe.db.{MacroDiagnostic, MacroOutput, MacroSeverity}
import loupe.hir.{
    macroBuildPlan,
    macroCallKeyOf,
    macroOutputOf,
    macroRequests,
    serverCalls,
    setMacroOutputsByKey
}
import loupe.vfs.VfsPath

func workspaceFixture(): Path {
    let root = Directory.createTemp(getTempDirectory())
    Directory.create(root.join("src"))
    File.writeTo(
        root.join("cjpm.toml"),
        #"[package]
name = "sample"
version = "0.1.0"
output-type = "executable"
"#.toArray()
    )
    File.writeTo(root.join("src/main.cj"), "package sample\nmain() { 1 }\n".toArray())
    root
}

@Test
class WorkspaceSessionTest {
    @TestCase
    func unchangedSynchronizationKeepsDatabaseQueriesAndRevision() {
        let root = workspaceFixture()
        let session = WorkspaceSession(VfsPath.file(root))
        try {
            let (db, revision, executions) =
                session
                    .withWorkspace {
                        state =>
                        let file = state.vfs.fileId(state.root.join("src/main.cj")).getOrThrow()
                        fileStructure(state.db, file)
                        (state.db, state.revision, state.db.storage.executions)
                    }
            session
                .withWorkspace {
                    state =>
                    @Expect(refEq(state.db, db))
                    @Expect(state.revision, revision)
                    let file = state.vfs.fileId(state.root.join("src/main.cj")).getOrThrow()
                    fileStructure(state.db, file)
                    @Expect(state.db.storage.executions, executions)
                }
            File.writeTo(root.join("src/added.cj"), "package sample\nfunc added() {}\n".toArray())
            session
                .withWorkspace {
                    state =>
                    @Expect(refEq(state.db, db))
                    @Expect(state.revision > revision)
                    @Expect(state.files.contains(state.root.join("src/added.cj")))
                }
            remove(root.join("src/added.cj"))
            session
                .withWorkspace {
                    state =>
                    @Expect(!state.files.contains(state.root.join("src/added.cj")))
                    @Expect(state.vfs.fileId(state.root.join("src/added.cj")).isNone())
                }
        } finally {
            session.close()
            remove(root, recursive: true)
        }
    }

    @TestCase
    func preparationWaitsUntilTheWholeScriptReturns() {
        let root = workspaceFixture()
        let session = WorkspaceSession(VfsPath.file(root))
        let entered = LinkedBlockingQueue<Bool>()
        let release = LinkedBlockingQueue<Bool>()
        let attempting = LinkedBlockingQueue<Bool>()
        let updated = AtomicBool(false)
        let script =
            spawn {
                try {
                    session
                        .withWorkspace {
                            state =>
                            let revision = state.revision
                            let file = state.vfs.fileId(state.root.join("src/main.cj")).getOrThrow()
                            let text = state.vfs.fileContents(file).getOrThrow().toString()
                            entered.add(true)
                            release.remove()
                            @Expect(!updated.load())
                            @Expect(state.revision, revision)
                            @Expect(state.vfs.fileContents(file).getOrThrow().toString(), text)
                        }
                } catch (e: Exception) {
                    throw e
                } catch (e: Error) {
                    throw e
                }
            }
        entered.remove()
        File.writeTo(root.join("src/main.cj"), "package sample\nmain() { 2 }\n".toArray())
        let preparing =
            spawn {
                try {
                    attempting.add(true)
                    session
                        .withWorkspace {
                            state =>
                            let file = state.vfs.fileId(state.root.join("src/main.cj")).getOrThrow()
                            @Expect(state.vfs.fileContents(file).getOrThrow().toString().contains("2"))
                            updated.store(true)
                        }
                } catch (e: Exception) {
                    throw e
                } catch (e: Error) {
                    throw e
                }
            }
        try {
            attempting.remove()
            release.add(true)
            script.get()
            preparing.get()
            @Expect(updated.load())
        } finally {
            session.close()
            remove(root, recursive: true)
        }
    }
}

@Test
class WorkspaceMacroSessionTest {
    @TestCase
    func macroProblemsKeepHintsAndMappedSourcePositions() {
        // arrange
        let root = workspaceFixture()
        Directory.create(root.join("src/ms"))
        File.writeTo(
            root.join("src/ms/macros.cj"),
            #"macro package sample.ms
import std.ast.*
public macro Pass(input: Tokens): Tokens { input }
"#.toArray()
        )
        let source =
            #"package sample
import sample.ms.*
// привет
@Pass public func value(): Int64 { 1 }
main() { value() }
"#
        File.writeTo(root.join("src/main.cj"), source.toArray())
        let session = WorkspaceSession(VfsPath.file(root))
        try {
            session
                .withWorkspace {
                    state =>
                    let fileId = state.vfs.fileId(state.root.join("src/main.cj")).getOrThrow()
                    let file = state.db.sourceFile(fileId).getOrThrow()
                    let call = serverCalls(state.db, file)[0].call
                    let previous = macroOutputOf(state.db, call).getOrThrow()
                    let request = macroRequests(state.db, file)[0]
                    let start = request.input.text.indexOf("value").getOrThrow()
                    let origin = request.input.originOf(TextRange(start, start + 5))
                    let diagnostic = MacroDiagnostic(
                        MacroSeverity.MacroError,
                        origin,
                        "invalid declaration",
                        "failure hint"
                    )
                    setMacroOutputsByKey(
                        state.db,
                        [
                            (
                                file,
                                macroCallKeyOf(state.db, call),
                                MacroOutput(previous.fingerprint, None, [], [diagnostic])
                            )
                        ]
                    )
                    let problems = ArrayList<String>()

                    // act
                    let complete = recordMacroProblems(state.db, state.vfs, [file], problems)

                    // assert
                    @Expect(!complete)
                    @Expect(problems.toArray(), ["${root.join("src/main.cj")}:4:19: invalid declaration: failure hint"])
                }
        } finally {
            session.close()
            remove(root, recursive: true)
        }
    }

    @TestCase
    func rebuiltLibraryReplacesCachedNestedExpansion() {
        let root = workspaceFixture()
        let macroDir = root.join("src/ms")
        Directory.create(macroDir)
        let source =
            #"macro package sample.ms
import std.ast.*
public macro Emit(input: Tokens): Tokens { quote(public func generated(): Int64 { 41 }) }
public macro Pass(input: Tokens): Tokens { input }
"#
        let mainSource =
            #"package sample
import sample.ms.*
import std.deriving.*
@Pass @Emit public func placeholder(): Int64 { 0 }
@Derive[Equatable] public struct Value { let n: Int64 = 1 }
main() { generated() }
"#
        File.writeTo(macroDir.join("macros.cj"), source.toArray())
        File.writeTo(root.join("src/main.cj"), mainSource.toArray())
        let session = WorkspaceSession(VfsPath.file(root))
        let stamps = ArrayList<Int64>()
        try {
            session
                .withWorkspace {
                    state =>
                    for (unit in macroBuildPlan(state.db) where unit.isMacro) {
                        stamps.add(unit.pkg.macroLibrary(state.db))
                    }
                    @Assert(state.problems, [])
                    @Assert(state.hasExpandedMacros)
                    @Expect(nestedExpansion(state, mainSource).contains("41"))
                }
            File.writeTo(macroDir.join("macros.cj"), source.replace("41", "42").toArray())
            @Assert(String.fromUtf8(File.readFrom(macroDir.join("macros.cj"))).contains("42"))
            session
                .withWorkspace {
                    state =>
                    @Assert(state.problems, [])
                    @Assert(state.hasExpandedMacros)
                    let file = state.vfs.fileId(state.root.join("src/ms/macros.cj")).getOrThrow()
                    @Expect(state.vfs.fileContents(file).getOrThrow().toString().contains("42"))
                    for (unit in macroBuildPlan(state.db) where unit.isMacro) {
                        @Expect(unit.pkg.macroLibrary(state.db) != stamps[0])
                    }
                    @Expect(nestedExpansion(state, mainSource).contains("42"))
                }
        } finally {
            session.close()
            remove(root, recursive: true)
        }
    }
}

func nestedExpansion(state: WorkspaceState, text: String): String {
    let file = state.vfs.fileId(state.root.join("src/main.cj")).getOrThrow()
    let call = macroCallAt(state.db, file, text.indexOf("@Pass").getOrThrow()).getOrThrow()
    expandedMacro(state.db, call.call).getOrThrow().text
}
