package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.{MappedSpan, SpanOrigin}
import loupe.fixture.{
    Annotation,
    Fixture,
    FixtureException,
    expectAnnotations,
    stdCjo,
    stdCjoRead,
    stdSourcesDir,
    stdWithSources
}
import rope.Rope

/**
 * Type targets at the cursor, annotated at the selected declaration names; no annotations means no targets.
 */
func checkTypeDefinition(fixture: String, std!: Array<String> = []): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database(binaries: std.map { name => stdCjoRead(name, stdCjo(name)) })
    let cursor = parsed.cursor ?? throw FixtureException("no cursor")
    let targets = typeDefinitionAt(db, cursor.fileId, cursor.offset)
    expectAnnotations(
        fixture,
        targets.map { target => Annotation(target.fileId, target.focusRange, "type") }
    )
}

@Test
class TypeDefinitionTest {
    @TestCase
    func aLocalGenericValueGoesToItsOwnParameter() {
        checkTypeDefinition(
            #"
            package m
            func f() {
                func id<T>(x: T): T {
            //          ^ type
                    let value = x
                    $0value
                }
            }
            "#
        )
    }

    @TestCase[code in [
        "func f() { let $0user = User(42) }",
        "func f() { let user = User(42); $0user }",
        "func f() { let user = $0User(42) }",
        "func f(user: $0User) {}",
        "func f($0user: User) {}",
        "func f(user: User) { $0user }",
        "let $0user = User(42)",
        "let $0user: User = User(42)",
        "let user = User(42); func f() { $0user }",
        "class Holder { let $0user: User = User(42) }",
        "class Holder { let user = User(42) }; func f(h: Holder) { h.$0user }",
        "class Holder { prop user: User { get() { User(42) } } }; func f(h: Holder) { h.$0user }"
    ]]
    func valuesAndDirectReferencesGoToTheType(code: String) {
        checkTypeDefinition(
            """
            //- /main.cj module=m package=m
            package m
            class User { init(id: Int64) {} }
            //    ^^^^ type
            ${code}
            """
        )
    }

    @TestCase[code in [
        "func f(box: Box<User>) { box.$0value }",
        "func f(box: Box<User>) { let user = box.value; $0user }",
        "func f(box: Box<User>) { box.$0item }"
    ]]
    func genericMemberTypesUseTheReceiverArguments(code: String) {
        checkTypeDefinition(
            """
            //- /main.cj module=m package=m
            package m
            class User {}
            //    ^^^^ type
            class Box<T> {
                let value: T
                init(value: T) { this.value = value }
                prop item: T { get() { value } }
            }
            ${code}
            """
        )
    }

    @TestCase
    func aPrimaryConstructorMemberUsesItsReceiverType() {
        checkTypeDefinition(
            #"
            //- /main.cj module=m package=m
            package m
            class User {}
            //    ^^^^ type
            class Box<T> { public Box(public let value: T) {} }
            func f(box: Box<User>) { box.$0value }
            "#
        )
    }

    @TestCase
    func aGenericInstanceGoesToItsOuterType() {
        checkTypeDefinition(
            #"
            //- /main.cj module=m package=m
            package m
            class User {}
            class Box<T> {}
            //    ^^^ type
            func f(box: Box<User>) { $0box }
            "#
        )
    }

    @TestCase[code in [
        "func f(user: $0Alias) {}",
        "func f(user: Alias) { $0user }",
        "func f(user: $0Identity<User>) {}",
        "func f() { let user: Identity<User> = User(); $0user }",
        "func f() { let user: $0Identity<User> = User() }",
        "type $0Other = Alias",
        "func f() { $0Alias() }",
        "func f() { $0Identity<User>() }"
    ]]
    func aliasesExpandToTheTypeTheyDenote(code: String) {
        checkTypeDefinition(
            """
            //- /main.cj module=m package=m
            package m
            class User {}
            //    ^^^^ type
            type Alias = User
            type Identity<T> = T
            ${code}
            """
        )
    }

    @TestCase[code in ["func f<T>(value: $0T) {}", "func f<T>(value: T) { $0value }"]]
    func aTypeParameterGoesToItsDeclaration(code: String) {
        checkTypeDefinition(
            """
            //- /main.cj module=m package=m
            package m
            ${code}
            //     ^ type
            """
        )
    }

    @TestCase
    func aWrittenLocalGenericParameterGoesToItsDeclaration() {
        checkTypeDefinition(
            #"
            //- /main.cj module=m package=m
            package m
            func outer() {
                func inner<T>(value: $0T) {}
            //             ^ type
            }
            "#
        )
    }

    @TestCase[code in [
        "func f(pair: (User, User)) { $0pair }",
        "func f(callback: () -> User) { $0callback }",
        "func make(): User { User() }; func f() { $0make() }",
        "func f(items: VArray<User, $2>) { $0items }",
        "func f(n: Int64) { $0n }",
        "func f(n: $0Int64) {}",
        "func f() { $0missing }",
        "func f(value: Missing) { $0value }",
        "type Alias = (User, User); func f(value: $0Alias) {}",
        "type Alias = Alias; func f(value: $0Alias) {}",
        "func f() { let value = \"text\"; $0value }"
    ]]
    func typesWithoutDeclarationsHaveNoTargets(code: String) {
        checkTypeDefinition(
            """
            //- /main.cj module=m package=m
            package m
            class User {}
            ${code}
            """
        )
    }

    @TestCase
    func aQualifiedTypeGoesAcrossFiles() {
        checkTypeDefinition(
            #"
            //- /lib/user.cj module=m package=m.lib
            package m.lib
            public class User {}
            //           ^^^^ type
            //- /main.cj module=m package=m
            package m
            import m.lib
            func f(user: lib.$0User) {}
            "#
        )
    }

    @TestCase
    func aBinaryTypeWithoutSourcesHasNoTarget() {
        checkTypeDefinition(
            #"
            //- /main.cj module=m package=m
            package m
            import std.collection.ArrayList
            func f(xs: ArrayList<Int64>) { $0xs }
            "#,
            std: ["std.core", "std.collection"]
        )
    }

    @TestCase
    func aBinaryTypeUsesCheckedSourceMapping() {
        // arrange
        let parsed =
            Fixture
                .parse(
                    #"
            //- /main.cj module=m package=m
            package m
            import std.collection.ArrayList
            func f(xs: ArrayList<Int64>) { $0xs }
            "#
                )
        let packages = ["std.core", "std.collection"]
        let db =
            parsed
                .database(
                    binaries: packages.map { name => stdCjoRead(name, stdCjo(name)) },
                    models: [stdWithSources(packages)]
                )
        let cursor = parsed.cursor ?? throw FixtureException("no cursor")

        // act
        let targets = typeDefinitionAt(db, cursor.fileId, cursor.offset)

        // assert
        @Assert(targets.size, 1)
        let target = targets[0]
        let source = db.sourceFile(target.fileId).getOrThrow()
        @Expect(parsed.pathOf(target.fileId), stdSourcesDir().join("collection").join("array_list.cj"))
        @Expect(source.text(db).slice(target.focusRange.start..target.focusRange.end).toString(), "ArrayList")

        // act
        db.setFileText(target.fileId, Rope("package std.collection\nclass Wrong {}"))
        let mismatched = typeDefinitionAt(db, cursor.fileId, cursor.offset)

        // assert
        @Expect(mismatched.isEmpty())
    }

    @TestCase
    func anExpandedParameterGoesToItsGeneratedType() {
        // arrange
        let (db, file, call, text) = answeredM()

        // act
        let targets = typeDefinitionInExpansion(db, call, offsetIn(text, "g: Gen"))

        // assert
        @Assert(targets.size, 1)
        @Expect(targets[0].fileId, file.fileId(db))
        @Expect(targets[0].expansion, Some(call))
        @Expect(text[targets[0].focusRange.start..targets[0].focusRange.end], "Gen")
    }
    @TestCase
    func aValueInAnExpressionExpansionUsesItsOwnerInference() {
        // arrange
        let (db, file) =
            expansionDatabase(
                #"
            package m
            import m.ms.*
            class User {}
            func f(user: User): User { @B(user) }
            "#
            )
        const TEXT = "user"
        let call =
            answer(db, file, "B", TEXT, [MappedSpan(TextRange(0, TEXT.size), SpanOrigin.FromCall)])

        // act
        let targets = typeDefinitionInExpansion(db, call, 0)

        // assert
        @Assert(targets.size, 1)
        @Expect(targets[0].fileId, file.fileId(db))
        @Expect(targets[0].expansion.isNone())
        @Expect(file.text(db).slice(targets[0].focusRange.start..targets[0].focusRange.end).toString(), "User")
    }
}
