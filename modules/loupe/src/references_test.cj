package loupe

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import rope.Rope
import loupe.fixture.*
import loupe.syntax.parse

/**
 * Checks the names `findReferences` finds at the `$0` of `fixture` are its annotations, each labeled with how it
 * reaches what it means, `text` for neither, and `decl` when it declares it; the packages of std named by
 * `binaries` read from the SDK.
 */
func checkReferences(fixture: String, binaries!: Array<String> = []): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database(binaries: binaries.map { name => stdCjoRead(name, stdCjo(name)) })
    let cursor = parsed.cursor ?? throw FixtureException("no $0 in the fixture")
    let found =
        findReferences(db, cursor.fileId, cursor.offset)
            .map {
                one =>
                let access = one.access.map { access => access.toString() } ?? "text"
                Annotation(
                    one.fileId,
                    one.range,
                    if (one.isDeclaration) { "${access} decl" } else { access }
                )
            }
    expectAnnotations(fixture, found)
}

/**
 * Checks the files `searchScope` searches for the name at the `$0` of `fixture` are those at `paths`, in order.
 */
func checkScope(fixture: String, paths: Array<String>): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database()
    let cursor = parsed.cursor ?? throw FixtureException("no $0 in the fixture")
    let file = db.sourceFile(cursor.fileId).getOrThrow()
    let token = tokenAt(parse(db, file).syntaxNode(), cursor.offset).getOrThrow()
    let scope = searchScope(db, meaningsAt(db, file, token), file).map { one => one.fileId(db) }
    @Expect(scope, paths.map {path => parsed.file(path).fileId})
}

@Test
class ReferencesTest {
    @TestCase
    func aPublicFunctionIsFoundInItsImportersAndNotANamesakeOfAnotherPackage() {
        checkReferences(
            #"
            //- /lib/a.cj module=lib package=lib
            package lib
            public func foo(): Int64 { 1 }
            //          ^^^ text decl
            func bar(): Int64 { foo() }
            //                  ^^^ read
            //- /lib/other/b.cj module=lib package=lib.other
            package lib.other
            public func foo(): Int64 { 2 }
            func baz(): Int64 { foo() }
            //- /app/main.cj module=app package=app deps=lib
            package app
            import lib.foo
            //         ^^^ text
            func f(): Int64 { f$0oo() + foo() }
            //                ^^^^^ read
            //                          ^^^ read
            "#
        )
    }

    @TestCase
    func aPrivateFunctionIsLookedForInItsFileOnly() {
        // cjc sees a private declaration in its own file only: another file's `hid` is not this one
        checkReferences(
            #"
            //- /a.cj module=m package=m
            package m
            private func hid(): Int64 { 1 }
            //           ^^^ text decl
            func f(): Int64 { h$0id() }
            //                ^^^^^ read
            //- /b.cj module=m package=m
            package m
            private func hid(): Int64 { 2 }
            func g(): Int64 { hid() }
            "#
        )
    }

    @TestCase
    func usesThroughAnImportsAliasAreFoundFromTheDeclarationAndFromTheAlias() {
        let fixture =
            #"
            //- /lib/a.cj module=lib package=lib
            package lib
            public func foo(): Int64 { 1 }
            //          ^^^ text decl
            //- /app/main.cj module=app package=app deps=lib
            package app
            import lib.foo as bar
            //         ^^^ text
            //                ^^^ text
            func f(): Int64 { bar() + b$0ar() }
            //                ^^^ read
            //                        ^^^^^ read
            //- /app/other.cj module=app package=app deps=lib
            package app
            import lib.foo
            //         ^^^ text
            func g(): Int64 { foo() }
            //                ^^^ read
            "#
        checkReferences(fixture)
    }

    @TestCase
    func ofOverloadsOnlyTheOneACallTakesAcrossFiles() {
        checkReferences(
            #"
            //- /a.cj module=m package=m
            package m
            public func g(n: Int64): Int64 { n }
            //          ^ text decl
            public func g(b: Bool): Int64 { 0 }
            //- /b.cj module=m package=m
            package m
            func f(): Int64 { $0g(1) + g(true) + g(2) }
            //                  ^ read
            //                                   ^ read
            "#
        )
    }

    @TestCase
    func aMemberIsFoundThroughAValueOfItsTypeInAModuleNotNamingIt() {
        checkReferences(
            #"
            //- /lib/a.cj module=lib package=lib
            package lib
            public class C {
                public func size(): Int64 { 0 }
            //              ^^^^ text decl
            }
            public class D {
                public func size(): Int64 { 1 }
            }
            public func make(): C { C() }
            public func other(): D { D() }
            //- /app/main.cj module=app package=app deps=lib
            package app
            import lib.{make, other}
            func f(): Int64 { make().si$0ze() + other().size() }
            //                       ^^^^^^ read
            "#
        )
    }

    @TestCase
    func aVarIsWrittenAndReadAcrossFiles() {
        checkReferences(
            #"
            //- /a.cj module=m package=m
            package m
            public var count = 0
            //         ^^^^^ write decl
            //- /b.cj module=m package=m
            package m
            func f(): Int64 {
                count += 1
            //  ^^^^^ write
                c$0ount
            //  ^^^^^^^ read
            }
            "#
        )
    }

    @TestCase
    func aMemberParameterOfAPrimaryConstructorIsFoundInOtherFiles() {
        checkReferences(
            #"
            //- /a.cj module=m package=m
            package m
            public class C {
                public C(public let si$0ze: Int64) {}
            //                      ^^^^^^ text decl
                public func twice(): Int64 { size * 2 }
            //                               ^^^^ read
            }
            //- /b.cj module=m package=m
            package m
            func f(c: C): Int64 { c.size }
            //                      ^^^^ read
            "#
        )
    }

    @TestCase
    func aTypeParameterIsFoundInItsDeclaration() {
        checkReferences(
            #"
            //- /a.cj module=m package=m
            package m
            func id<T>(x: $0T): T { x }
            //      ^ text decl
            //              ^ text
            //                  ^ text
            //- /b.cj module=m package=m
            package m
            class T {}
            "#
        )
    }

    @TestCase
    func aTypeParameterOfAFunctionABodyDeclaresIsFoundFromItsDeclaration() {
        checkReferences(
            #"
            //- /a.cj module=m package=m
            package m
            func f(): Unit {
                func g<$0T>(x: T): T {
            //           ^ text decl
            //                 ^ text
            //                     ^ text
                    let y: T = x
            //             ^ text
                    y
                }
            }
            func h<T>(x: T): T { x }
            "#
        )
    }

    @TestCase
    func aFunctionOfStdIsFoundInEveryPackageAndNotDeclaredInTheWorkspace() {
        checkReferences(
            #"
            //- /a.cj module=m package=m
            package m
            func f(): Unit { print$0ln("a") }
            //               ^^^^^^^^^ read
            //- /b/b.cj module=n package=n
            package n
            func g(): Unit { println("b") }
            //               ^^^^^^^ read
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func aKeywordHasNoReferences() {
        checkReferences(
            #"
            //- /a.cj module=m package=m
            package m
            fu$0nc f(): Int64 { 1 }
            "#
        )
    }

    @TestCase
    func aNameMeaningNothingHasNoReferences() {
        checkReferences(
            #"
            //- /a.cj module=m package=m
            package m
            func f(): Int64 { nothi$0ng }
            "#
        )
    }

    @TestCase
    func anInternalDeclarationIsLookedForInItsPackageAndThoseUnderIt() {
        // arrange
        let fixture =
            #"
            //- /lib/a.cj module=lib package=lib.a
            package lib.a
            func fo$0o(): Int64 { 1 }
            //- /lib/a/sub/b.cj module=lib package=lib.a.sub
            package lib.a.sub
            //- /lib/c.cj module=lib package=lib.c
            package lib.c
            //- /app/main.cj module=app package=app deps=lib
            package app
            "#

        // act, assert
        checkScope(fixture, ["/lib/a.cj", "/lib/a/sub/b.cj"])
    }

    @TestCase
    func aPublicDeclarationIsLookedForInTheModulesThatMayImportIt() {
        // arrange
        let fixture =
            #"
            //- /lib/a.cj module=lib package=lib
            package lib
            public func fo$0o(): Int64 { 1 }
            //- /app/main.cj module=app package=app deps=lib
            package app
            //- /tool/main.cj module=tool package=tool
            package tool
            "#

        // act, assert
        checkScope(fixture, ["/lib/a.cj", "/app/main.cj"])
    }

    @TestCase
    func aPrivateMemberIsLookedForInItsFileAndAnyOtherInEveryFile() {
        // arrange
        let fixture =
            #"
            //- /a.cj module=m package=m
            package m
            public class C {
                private func hi$0d(): Int64 { 1 }
                public func shown(): Int64 { hid() }
            }
            //- /b.cj module=m package=m
            package m
            //- /app/main.cj module=app package=app
            package app
            "#

        // act, assert
        checkScope(fixture, ["/a.cj"])
        checkScope(
            fixture.replace("hi$0d(): Int64 { 1 }", "hid(): Int64 { 1 }").replace("sho", "s$0ho"),
            ["/a.cj", "/b.cj", "/app/main.cj"]
        )
    }

    @TestCase
    func aLocalIsLookedForInItsFileOnly() {
        // arrange
        let fixture =
            #"
            //- /a.cj module=m package=m
            package m
            func f(): Int64 {
                let lo$0cal = 1
                local
            }
            //- /b.cj module=m package=m
            package m
            "#

        // act, assert
        checkScope(fixture, ["/a.cj"])
    }
}

@Test
class ReferencesSearchTest {
    @TestCase
    func aFileNamingTheNameOnlyInsideALongerWordIsNotParsed() {
        // arrange - `b.cj` has `foo` in `fooBar` and in `food`, never as a word of its own
        let parsed =
            Fixture
                .parse(
                    #"
            //- /a.cj module=m package=m
            package m
            public func f$0oo(): Int64 { 1 }
            //- /b.cj module=m package=m
            package m
            public func fooBar(): Int64 { 2 } // food
            "#
                )
        let db = parsed.database()
        let a = parsed.file("/a.cj").fileId
        parse(db, db.sourceFile(a).getOrThrow())
        let runs = db.storage.executionsOf("parse")

        // act
        let found = findReferences(db, a, parsed.cursor.getOrThrow().offset)

        // assert
        @Expect(found.size, 1)
        @Expect(db.storage.executionsOf("parse"), runs)
    }

    @TestCase
    func anEditMakesTheWordsOfTheEditedFileAgainAndNoOthers() {
        // arrange
        let parsed =
            Fixture
                .parse(
                    #"
            //- /a.cj module=m package=m
            package m
            public func f$0oo(): Int64 { 1 }
            //- /b.cj module=m package=m
            package m
            func g(): Int64 { foo() }
            //- /c.cj module=m package=m
            package m
            func h(): Int64 { 3 }
            "#
                )
        let db = parsed.database()
        let a = parsed.file("/a.cj").fileId
        let offset = parsed.cursor.getOrThrow().offset
        findReferences(db, a, offset)
        let runs = db.storage.executionsOf("fileWords")
        db.setFileText(parsed.file("/c.cj").fileId, Rope("package m\nfunc h(): Int64 { foo() }\n"))

        // act
        let found = findReferences(db, a, offset)

        // assert
        @Expect(db.storage.executionsOf("fileWords"), runs + 1)
        @Expect(found.map {one => one.fileId}, [a, parsed.file("/b.cj").fileId, parsed.file("/c.cj").fileId])
    }
}
