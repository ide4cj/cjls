package loupe.hir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.AnalysisDatabase
import loupe.fixture.*
import loupe.syntax.parse

/**
 * The database of `parsed`, with the `.cjo`s of std.core and of std.unittest's packages among its packages.
 */
func databaseWithUnittest(parsed: Fixture): AnalysisDatabase {
    parsed.database(binaries: ["std.core", "std.unittest", "std.unittest.common", "std.unittest.testmacro"].map {
        name => stdCjoRead(name, stdCjo(name))
    })
}

/**
 * The text of each expansion of a macro call on the item of the first file of `fixture` at `index` among its items,
 * outermost call first.
 */
func unittestExpansionsAt(fixture: String, index: Int64): Array<String> {
    let parsed = Fixture.parse(fixture)
    let db = databaseWithUnittest(parsed)
    let file = db.sourceFile(parsed.files[0].fileId).getOrThrow()
    let item = itemTree(db, file).items.get(index) ?? throw FixtureException("no item ${index} in the fixture")
    expandedCalls(db, file).filter {call => call.item(db) == item.id}.map {call => macroExpansion(db, call).text}
}

/**
 * What std.unittest's macros declare (#175), as `cjc --debug-macro` (1.3.0-alpha.20260918) shows it but for the
 * bodies, the `private` helpers and the registrations of options: what a name can reach.
 */
@Test
class UnittestExpansionTest {
    @TestCase
    func aTestClassIsATestClassAndRegistered() {
        // act
        let texts = unittestExpansionsAt(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test
            public class C {
                @TestCase
                func t(): Unit {}
            }
            "#, 0)

        // assert
        @Expect(texts, [
            "extend C <: TestClass {\n" +
            "    public func asTestSuite(): TestSuite {}\n" +
            "}\n" +
            "interface TestPackageExtension_C {\n" +
            "    func registerC(): Unit\n" +
            "}\n" +
            "extend TestPackage <: TestPackageExtension_C {\n" +
            "    public func registerC(): Unit {}\n" +
            "}\n"])
    }

    @TestCase
    func aGenericTestClassKeepsItsTypeParametersAndConstraints() {
        // act
        let texts = unittestExpansionsAt(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test
            @Types[T in <Int64>]
            class C<T> where T <: ToString {
                C() {}
            }
            "#, 0)

        // assert
        @Expect(texts, [
            "extend<T> C<T> <: TestClass where T <: ToString {\n" +
            "    public func asTestSuite(): TestSuite {}\n" +
            "}\n" +
            "interface TestPackageExtension_C {\n" +
            "    func registerC(): Unit\n" +
            "}\n" +
            "extend TestPackage <: TestPackageExtension_C {\n" +
            "    public func registerC(): Unit {}\n" +
            "}\n"])
    }

    @TestCase
    func aTestClassMadeOfArgumentsAloneIsNotRegistered() {
        // act
        let texts = unittestExpansionsAt(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test
            class C {
                init(x: Int64) {}
            }
            "#, 0)

        // assert
        @Expect(texts, ["extend C <: TestClass {\n    public func asTestSuite(): TestSuite {}\n}\n"])
    }

    @TestCase
    func aTestTemplateIsATestClassNotRegistered() {
        // act
        let texts = unittestExpansionsAt(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @TestTemplate
            abstract class T {}
            "#, 0)

        // assert
        @Expect(texts, ["extend T <: TestClass {\n    public func asTestSuite(): TestSuite {}\n}\n"])
    }

    @TestCase
    func aTestFunctionGetsATestClassOfItsOwn() {
        // act
        let texts = unittestExpansionsAt(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test
            func f(): Unit {}
            "#, 0)

        // assert
        @Expect(texts, [
            "class TestCase_f <: TestClass {\n" +
            "    public func asTestSuite(): TestSuite {}\n" +
            "}\n" +
            "interface TestPackageExtension_TestCase_f {\n" +
            "    func registerTestCase_f(): Unit\n" +
            "}\n" +
            "extend TestPackage <: TestPackageExtension_TestCase_f {\n" +
            "    public func registerTestCase_f(): Unit {}\n" +
            "}\n"])
    }

    @TestCase
    func aTestBuilderIsRegistered() {
        // act
        let texts = unittestExpansionsAt(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @TestBuilder
            func b(): TestSuite { TestSuite.builder("b").build() }
            "#, 0)

        // assert
        @Expect(texts, [
            "interface TestPackageExtension_b {\n" +
            "    func register_b(): Unit\n" +
            "}\n" +
            "extend TestPackage <: TestPackageExtension_b {\n" +
            "    public func register_b(): Unit {}\n" +
            "}\n"])
    }

    @TestCase
    func onlyTheOutermostOfTestAndTestBuilderRewritesTheItem() {
        // act
        let texts = unittestExpansionsAt(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Tag[fast]
            @TestBuilder
            @Test
            func b(): TestSuite { TestSuite.builder("b").build() }
            "#, 0)

        // assert
        @Expect(texts.size, 1)
        @Expect(texts[0].startsWith("interface TestPackageExtension_b {"))
    }

    @TestCase
    func aStrategyIsALetOfItsNameAndModifiers() {
        // act
        let texts = unittestExpansionsAt(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Strategy[x in [1, 2]]
            public func strat(x: Int64): Array<Int64> { [x] }
            "#, 0)

        // assert
        @Expect(texts, ["public let strat: DataStrategyProcessor<Array<Int64>>\n"])
    }

    @TestCase
    func aStrategyWithoutAReturnTypeIsALetOfNoType() {
        // act
        let texts = unittestExpansionsAt(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Strategy
            func strat() { 1 }
            "#, 0)

        // assert
        @Expect(texts, ["let strat\n"])
    }

    @TestCase
    func anOptionIsTheStructOfItsKey() {
        // act
        let texts = unittestExpansionsAt(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @UnittestOption[Int64, Array<String>](public zxc, "an option")
            "#, 0)

        // assert
        @Expect(texts, [
            "public struct KeyZxc <: KeyFor<Int64> & KeyFor<Array<String>> {\n" +
            "    public static prop zxc: KeyZxc {\n" +
            "        get() {}\n" +
            "    }\n" +
            "    public prop name: String {\n" +
            "        get() {}\n" +
            "    }\n" +
            "}\n"])
    }

    @TestCase
    func anOptionNotPublicIsInternal() {
        // act
        let texts = unittestExpansionsAt(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @UnittestOption[Bool](opt)
            "#, 0)

        // assert
        @Expect(texts.size, 1)
        @Expect(texts[0].startsWith("struct KeyOpt <: KeyFor<Bool> {\n"))
    }

    @TestCase
    func anOptionWithoutTypesOrANameDeclaresNothing() {
        // act
        let noTypes = unittestExpansionsAt(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.testmacro.*
            @UnittestOption(opt)
            "#, 0)
        let noName = unittestExpansionsAt(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.testmacro.*
            @UnittestOption[Bool]("opt")
            "#, 0)

        // assert
        @Expect(noTypes, [""])
        @Expect(noName, [""])
    }

    @TestCase
    func packagesImportingEachOtherExpandBothNoCycleOfQueries() {
        // arrange - a cycle of plain imports (cjpm rejects it), each package with an expansion and an import of a name
        let parsed = Fixture.parse(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            import std.unittest.*
            import std.unittest.testmacro.*
            import m.b.KeyB
            @UnittestOption[Int64](public a)
            @Test
            class A {}
            //- /b/b.cj module=m package=m.b
            package m.b
            import std.unittest.*
            import std.unittest.testmacro.*
            import m.a.KeyA
            @UnittestOption[Int64](public b)
            @Test
            class B {}
            "#)
        let db = databaseWithUnittest(parsed)
        let a = db.sourceFile(parsed.files[0].fileId).getOrThrow()
        let pkg = packageOfFile(db, a).getOrThrow()

        // act
        let calls = expandedCalls(db, a).size
        let found = lookUp(db, pkg, a, "KeyB", Namespace.Types)

        // assert
        @Expect(calls, 2)
        @Expect(found.toString().startsWith("found"))
    }

    @TestCase
    func theFunctionAStrategyReplacesIsNoDeclarationOfThePackage() {
        // arrange
        let parsed = Fixture.parse(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Strategy[x in [1, 2]]
            func strat(x: Int64): Int64 { x }
            "#)
        let db = databaseWithUnittest(parsed)
        let file = db.sourceFile(parsed.files[0].fileId).getOrThrow()
        let pkg = packageOfFile(db, file).getOrThrow()

        // act
        let defs = defMap(db, PackageRef.Source(pkg))
        let written = defMapAt(db, PackageRef.Source(pkg), ScopeStage.Written)

        // assert
        let strats = defs.names.get("strat") ?? []
        @Expect(strats.size, 1)
        @Expect(strats[0].id.item(db).kind == ItemKind.Var)
        @Expect(defs.errors.size, 0)
        let writtenStrats = written.names.get("strat") ?? []
        @Expect(writtenStrats.size, 1)
        @Expect(writtenStrats[0].id.item(db).kind == ItemKind.Func)
    }

    @TestCase
    func aTestOfTheUserIsNotStds() {
        // act
        let texts = unittestExpansionsAt(#"
            //- /main.cj module=m package=m
            package m
            import m.ms.*
            @Test
            class C {}
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro Test(input: Tokens): Tokens { input }
            "#, 0)

        // assert
        @Expect(texts, [])
    }

    @TestCase
    func testNotImportedExpandsNothing() {
        // act
        let texts = unittestExpansionsAt(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            @Test
            class C {}
            "#, 0)

        // assert
        @Expect(texts, [])
    }
}

/**
 * Checks the types inference gives the bodies of the first file of `fixture`, with std.core and std.unittest's
 * packages.
 */
func checkInferenceWithUnittest(fixture: String): Unit {
    let parsed = Fixture.parse(fixture)
    let db = databaseWithUnittest(parsed)
    let actual = ArrayList<Annotation>()
    let source = db.sourceFile(parsed.files[0].fileId).getOrThrow()
    let root = parse(db, source).syntaxNode()
    for (item in itemTree(db, source).items) {
        annotateTypes(db, source, root, item, actual)
    }
    expectAnnotations(fixture, actual.toArray())
}

/**
 * What std.unittest's macros declare, read as any declaration of the package (#175): a test class's `asTestSuite`, an
 * option's key, a strategy's `let` in the place of its function.
 */
@Test
class UnittestInferenceTest {
    @TestCase
    func aTestClassIsATestClass() {
        checkInferenceWithUnittest(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test
            class C {}
            func id<T>(x: T): T where T <: TestClass { x }
            //         ^ T
            func f(c: C): Unit {
            //     ^ C
                let s = c.asTestSuite()
            //      ^ TestSuite
                let i = id(c)
            //      ^ C
                let t = TestCase_g().asTestSuite()
            //      ^ TestSuite
            }
            @Test
            func g(): Unit {}
            "#)
    }

    @TestCase
    func anOptionIsItsKey() {
        checkInferenceWithUnittest(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @UnittestOption[Int64](public zxc)
            func f(c: Configuration): Unit {
            //     ^ Configuration
                let key = KeyZxc.zxc
            //      ^^^ KeyZxc
                let name = key.name
            //      ^^^^ String
                let value = c.get(KeyZxc.zxc)
            //      ^^^^^ Option<Int64>
            }
            "#)
    }

    @TestCase
    func aStrategyIsAProcessorOfWhatItsFunctionReturns() {
        checkInferenceWithUnittest(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Strategy[x in [1, 2]]
            func strat(x: Int64): Int64 { x }
            //         ^ Int64
            func f(): Unit {
                let s = strat
            //      ^ DataStrategyProcessor<Int64>
            }
            "#)
    }

    @TestCase
    func theMacrosOfStdUnittestOnMembersAddNothingUnknown() {
        checkUnknowns(#"
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test
            @Configure[parallel: false]
            class C {
                let x = 1
                @TestCase
                @Tag[fast]
                func t(): Unit {}
            }
            func f(c: C): Unit {
                let s = c.asTestSuite()
                let x = c.x
                let t = c.t()
                // cjc: 'nothing' is not a member of class 'C'
                let n = c.nothing
            //          ^^^^^^^^^ error
            }
            "#, binaries: ["std.core", "std.unittest", "std.unittest.common", "std.unittest.testmacro"])
    }

    @TestCase
    func theMacrosOfStdDerivingAddNothingUnknown() {
        checkUnknowns(#"
            package m
            import std.deriving.*
            @Derive[Hashable]
            struct S {
                @DeriveExclude
                let x: Int64 = 1
            }
            func f(s: S): Unit {
                let h = s.hashCode()
                // cjc: 'nothing' is not a member of struct 'S'
                let n = s.nothing
            //          ^^^^^^^^^ error
            }
            "#, binaries: ["std.core", "std.deriving"])
    }

    @TestCase
    func aStrategyOnAMemberIsNotExpandedSoItsClassIsNotKnown() {
        checkUnknowns(#"
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test
            class C {
                @Strategy[x in [1]]
                func s(x: Int64): Int64 { x }
            }
            func f(c: C): Unit {
                let n = c.nothing
            //          ^^^^^^^^^ todo(macro member)
            }
            "#, binaries: ["std.core", "std.unittest", "std.unittest.common", "std.unittest.testmacro"])
    }

    @TestCase
    func theDeclarationsOfATestOfTheUserAreNotStds() {
        checkInferenceWithUnittest(#"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import m.ms.*
            @Test
            class C {}
            func f(c: C): Unit {
            //     ^ C
                let s = c.asTestSuite()
            //      ^ {unknown}
            }
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro Test(input: Tokens): Tokens { input }
            "#)
    }
}
