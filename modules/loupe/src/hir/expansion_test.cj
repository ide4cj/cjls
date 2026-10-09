package loupe.hir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.AnalysisDatabase
import loupe.fixture.*
import loupe.syntax.parse

/**
 * The database of `parsed`, with std.core's and std.deriving's `.cjo`s among its packages.
 */
func databaseWithDerive(parsed: Fixture): AnalysisDatabase {
    parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core")),
        stdCjoRead("std.deriving", stdCjo("std.deriving"))])
}

/**
 * The text of each expansion of a macro call on the declaration `name` of the first file of `fixture`, outermost
 * call first.
 */
func expansionsNamed(fixture: String, name: String): Array<String> {
    let parsed = Fixture.parse(fixture)
    let db = databaseWithDerive(parsed)
    let file = db.sourceFile(parsed.files[0].fileId).getOrThrow()
    let item = itemTree(db, file).items.iterator().filter {item => item.names.contains(name)}.next() ??
        throw FixtureException("no ${name} in the fixture")
    expandedCalls(db, file).filter {call => call.item(db) == item.id}.map {call => macroExpansion(db, call).text}
}

/**
 * What std's `@Derive` adds after a type (#175): an `extend` per interface, signatures alone, as
 * `cjc --debug-macro` (1.3.0-alpha.20261002) shows it but for the bodies and the `private` checks.
 */
@Test
class DeriveExpansionTest {
    @TestCase
    func anExtendPerInterfaceOfATypeOfNoTypeParameters() {
        // act
        let texts = expansionsNamed(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Hashable, ToString]
            struct S {
                let x: Int64 = 0
            }
            "#, "S")

        // assert
        @Expect(texts, [
            "extend S <: Hashable {\n" +
            "    public func hashCode(): Int64 {}\n" +
            "}\n" +
            "extend S <: ToString {\n" +
            "    public func toString(): String {}\n" +
            "}\n"])
    }

    @TestCase
    func eachTypeParameterIsBoundByTheInterface() {
        // act
        let texts = expansionsNamed(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Equatable, Arbitrary, Shrink]
            class P<K, V> {}
            "#, "P")

        // assert
        @Expect(texts, [
            "extend<K, V> P<K, V> <: Equatable<P<K, V>> where K <: Equatable<K>, V <: Equatable<V> {\n" +
            "    public operator func ==(other: P<K, V>): Bool {}\n" +
            "    public operator func !=(other: P<K, V>): Bool {}\n" +
            "}\n" +
            "extend<K, V> P<K, V> <: Arbitrary<P<K, V>> where K <: Arbitrary<K>, V <: Arbitrary<V> {\n" +
            "    public static func arbitrary(random: RandomSource): Generator<P<K, V>> {}\n" +
            "}\n" +
            "extend<K, V> P<K, V> <: Shrink<P<K, V>> where K <: Shrink<K>, V <: Shrink<V> {\n" +
            "    public func shrink(): Iterable<P<K, V>> {}\n" +
            "}\n"])
    }

    @TestCase
    func aWhereReplacesTheBoundOfTheParametersItNamesForItsInterfaceAlone() {
        // act
        let texts = expansionsNamed(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Hashable where K <: Hashable & Equatable<K>, ToString]
            enum E<K, V> {
                | A(K) | B(V)
            }
            "#, "E")

        // assert
        @Expect(texts, [
            "extend<K, V> E<K, V> <: Hashable where K <: Hashable & Equatable<K>, V <: Hashable {\n" +
            "    public func hashCode(): Int64 {}\n" +
            "}\n" +
            "extend<K, V> E<K, V> <: ToString where K <: ToString, V <: ToString {\n" +
            "    public func toString(): String {}\n" +
            "}\n"])
    }

    @TestCase
    func aWhereOfSeveralConstraintsBeforeTheNextInterface() {
        // act
        let texts = expansionsNamed(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Hashable where K <: Hashable, V <: Hashable & ToString, ToString]
            class C<K, V> {}
            "#, "C")

        // assert
        @Expect(texts, [
            "extend<K, V> C<K, V> <: Hashable where K <: Hashable, V <: Hashable & ToString {\n" +
            "    public func hashCode(): Int64 {}\n" +
            "}\n" +
            "extend<K, V> C<K, V> <: ToString where K <: ToString, V <: ToString {\n" +
            "    public func toString(): String {}\n" +
            "}\n"])
    }

    @TestCase
    func comparableAddsEquatableAfterItOfTheDefaultBound() {
        // act
        let texts = expansionsNamed(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Comparable where T <: Comparable<T> & ToString]
            struct R<T> {}
            "#, "R")

        // assert
        @Expect(texts, [
            "extend<T> R<T> <: Comparable<R<T>> where T <: Comparable<T> & ToString {\n" +
            "    public func compare(other: R<T>): Ordering {}\n" +
            "    public operator func <(other: R<T>): Bool {}\n" +
            "    public operator func <=(other: R<T>): Bool {}\n" +
            "    public operator func >(other: R<T>): Bool {}\n" +
            "    public operator func >=(other: R<T>): Bool {}\n" +
            "}\n" +
            "extend<T> R<T> <: Equatable<R<T>> where T <: Equatable<T> {\n" +
            "    public operator func ==(other: R<T>): Bool {}\n" +
            "    public operator func !=(other: R<T>): Bool {}\n" +
            "}\n"])
    }

    @TestCase
    func comparableAddsNoEquatableTheCallLists() {
        // act
        let texts = expansionsNamed(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Equatable, Comparable]
            struct S {}
            "#, "S")

        // assert
        @Expect(texts.size, 1)
        @Expect(texts[0].split("\n").filter {line => line.startsWith("extend")},
            ["extend S <: Equatable<S> {", "extend S <: Comparable<S> {"])
    }

    @TestCase
    func anInterfaceItDoesNotKnowAddsNothing() {
        // act
        let texts = expansionsNamed(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Foo, Hashable]
            struct S {}
            "#, "S")

        // assert
        @Expect(texts, ["extend S <: Hashable {\n    public func hashCode(): Int64 {}\n}\n"])
    }

    @TestCase
    func eachCallOfSeveralIsAnExpansionOutermostFirst() {
        // act
        let texts = expansionsNamed(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Hashable]
            @Derive[ToString]
            struct S {}
            "#, "S")

        // assert
        @Expect(texts, ["extend S <: Hashable {\n    public func hashCode(): Int64 {}\n}\n",
            "extend S <: ToString {\n    public func toString(): String {}\n}\n"])
    }

    @TestCase
    func deriveOfThePackageImportedByItsName() {
        // act
        let texts = expansionsNamed(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving
            @deriving.Derive[Hashable]
            struct S {}
            "#, "S")

        // assert
        @Expect(texts, ["extend S <: Hashable {\n    public func hashCode(): Int64 {}\n}\n"])
    }

    @TestCase
    func aDeriveOfTheUserIsNotStds() {
        // act
        let texts = expansionsNamed(#"
            //- /main.cj module=m package=m
            package m
            import m.ms.*
            @Derive[Hashable]
            struct S {}
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro Derive(attr: Tokens, input: Tokens): Tokens { input }
            "#, "S")

        // assert
        @Expect(texts, [])
    }

    @TestCase
    func deriveNotImportedExpandsNothing() {
        // act
        let texts = expansionsNamed(#"
            //- /main.cj module=m package=m
            package m
            @Derive[Hashable]
            struct S {}
            "#, "S")

        // assert
        @Expect(texts, [])
    }
}

/**
 * Checks the types inference gives the bodies of the first file of `fixture`, with std.core and std.deriving.
 */
func checkInferenceWithDerive(fixture: String): Unit {
    let parsed = Fixture.parse(fixture)
    let db = databaseWithDerive(parsed)
    let actual = ArrayList<Annotation>()
    let source = db.sourceFile(parsed.files[0].fileId).getOrThrow()
    let root = parse(db, source).syntaxNode()
    for (item in itemTree(db, source).items) {
        annotateTypes(db, source, root, item, actual)
    }
    expectAnnotations(fixture, actual.toArray())
}

/**
 * A type `@Derive` makes of an interface (#175): its members found after a `.` and by an operator, its type meeting
 * the interface as a bound, as any `extend`'s of its package.
 */
@Test
class DeriveInferenceTest {
    @TestCase
    func aDerivedMemberAfterADot() {
        checkInferenceWithDerive(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Hashable, ToString]
            struct S {}
            func f(s: S): Unit {
            //     ^ S
                let h = s.hashCode()
            //      ^ Int64
                let t = s.toString()
            //      ^ String
            }
            "#)
    }

    @TestCase
    func aDerivedOperatorOfAGenericType() {
        checkInferenceWithDerive(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Comparable]
            class P<T> {
                P(let x: T) {}
            //        ^ T
            }
            func f(a: P<Int64>, b: P<Int64>): Unit {
            //     ^ P<Int64>
            //                  ^ P<Int64>
                let e = a == b
            //      ^ Bool
                let l = a < b
            //      ^ Bool
                let o = a.compare(b)
            //      ^ Ordering
            }
            "#)
    }

    @TestCase
    func aDerivedTypeMeetsTheInterfaceAsABound() {
        checkInferenceWithDerive(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Hashable]
            struct S {}
            struct N {}
            func id<T>(x: T): T where T <: Hashable { x }
            //         ^ T
            func f(): Unit {
                let s = id(S())
            //      ^ S
                // cjc: unable to infer generic argument of this function
                let n = id(N())
            //      ^ {unknown}
            }
            "#)
    }

    @TestCase
    func theMembersOfADeriveOfTheUserAreNotStds() {
        checkInferenceWithDerive(#"
            //- /main.cj module=m package=m
            package m
            import m.ms.*
            @Derive[Hashable]
            struct S {}
            func f(s: S): Unit {
            //     ^ S
                let h = s.hashCode()
            //      ^ {unknown}
            }
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro Derive(attr: Tokens, input: Tokens): Tokens { input }
            "#)
    }
}
