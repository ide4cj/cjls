package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*
import rope.Rope

@Test
class RedeclarationDiagnosticsTest {
    @TestCase
    func duplicateBindingsAndMembers(): Unit {
        checkDiagnostics(
            #"
            class C {
                let x = 1
                let x = 2
            //      ^ error: redefinition of declaration 'x'
            }
            func f(): Unit {
                let x = 1
                let x = 2
            //      ^ error: redefinition of declaration 'x'
                let (a, a) = (1, 2)
            //          ^ error: redefinition of declaration 'a'
            }
            "#
        )
    }

    @TestCase
    func conflictingOverloadsIgnoreReturnTypesAndParameterNames(): Unit {
        checkDiagnostics(
            #"
            func f(x: Int64): Int64 { x }
            func f(y!: Int64): String { "x" }
            //   ^ error: function 'f' has overload conflicts
            func generic<T>(x: T): Unit {}
            func generic<U>(x: U): Unit {}
            //   ^^^^^^^ error: function 'generic' has overload conflicts
            func outer(): Unit {
                func local(x: Int64): Unit {}
                func local(y: Int64): Unit {}
            //       ^^^^^ error: function 'local' has overload conflicts
            }
            class C {
                func m(): Int64 { 1 }
                func m(): String { "x" }
            //       ^ error: function 'm' has overload conflicts
            }
            "#
        )
    }

    @TestCase
    func repeatedMethodsReportEveryConflict(): Unit {
        // arrange
        const METHOD = "    func f(x: Int64): Int64 { x + 1 }\n"
        let methods = String.join(Array(2000) { _ => METHOD })
        let fixture = Fixture.parse("class A {\n${methods}}\n")
        let db = fixture.database()
        // act
        let found = diagnostics(db, fixture.file("/main.cj").fileId)

        // assert
        @Expect(found.size, 1999)
        @Expect(found.all { one => one.message == "function 'f' has overload conflicts" })
    }

    @TestCase
    func parametersShareTheOutermostBodyScope(): Unit {
        checkDiagnostics(
            #"
            func f(x: Int64): Unit {
                let x = 1
            //      ^ error: redefinition of declaration 'x'
            }
            func g(x: Int64, x: Int64): Unit {}
            //               ^ error: redefinition of declaration 'x'
            "#
        )
    }

    @TestCase
    func distinctOverloadsAndNestedShadowingAreValid(): Unit {
        checkDiagnostics(
            #"
            func f(x: Int64): Int64 { x }
            func f(x: String): String { x }
            func g(x: Int64): Unit {
                if (true) { let x = 1 }
                if (true) { let x = 2 }
                let h = { x: Int64 => x }
                func m(x: Int64): Unit {}
                func m(x: String): Unit {}
            }
            func generic<T>(x: T): Unit {}
            func generic<T, U>(x: T): Unit {}
            enum E { X(Int64) | X(Int64, String) }
            class A { let x = 1 }
            class B { let x = 2 }
            "#
        )
    }

    @TestCase
    func staticAndInstanceOverloadsCannotMix(): Unit {
        checkDiagnostics(
            #"
            class C {
                static func f(x: Int64): Unit {}
                func f(x: String): Unit {}
            //       ^ error: overloaded functions 'f' cannot mix static and non-static
            }
            "#
        )
    }

    @TestCase
    func theLastConflictingOverloadDeterminesTheMessage(): Unit {
        checkDiagnostics(
            #"
            class C {
                static func f(x: Int64): Unit {}
                func f(x: UInt32): Unit {}
            //       ^ error: overloaded functions 'f' cannot mix static and non-static
                func f(x: UInt32): Unit {}
            //       ^ error: function 'f' has overload conflicts
                func f(x: Int64): Unit {}
            //       ^ error: overloaded functions 'f' cannot mix static and non-static
            }
            "#
        )
    }

    @TestCase
    func constructorMembersAndOverloadsShareTheirTypesScope(): Unit {
        checkDiagnostics(
            #"
            class C {
                C(let x: Int64) {}
                let x = 2
            //      ^ error: redefinition of declaration 'x'
                init(y: Int64) {}
            //  ^^^^ error: constructor 'init' has overload conflicts
            }
            class D {
                let x = 2
                D(let x: Int64) {}
            //        ^ error: redefinition of declaration 'x'
            }
            class E {
                init(x: Int64) {}
                init(y: Int64) {}
            //  ^^^^ error: constructor 'init' has overload conflicts
            }
            class Valid {
                static init() {}
                init() {}
                init(x: Int64) {}
                init(x: String) {}
            }
            "#
        )
    }

    @TestCase
    func declarationEditClearsAnUneditedFilesConflict(): Unit {
        let fixture = Fixture.parse(
            #"
            //- /a.cj module=a package=a
            func f(): Int64 { 1 }
            //- /b.cj module=a package=a
            func f(): Int64 { 2 }
            "#
        )
        let db = fixture.database()
        let first = fixture.file("/a.cj").fileId
        let second = fixture.file("/b.cj").fileId
        @Expect(diagnostics(db, second).size, 1)
        db.setFileText(first, Rope("func f(x: Int64): Int64 { x }"))
        @Expect(diagnostics(db, second).isEmpty())
        db.setFileText(first, Rope("func f(): Int64 { 1 }"))
        @Expect(diagnostics(db, second).size, 1)
    }

    @TestCase
    func macroAttributeAndPlainAritiesAreValid(): Unit {
        checkDiagnostics(
            #"
            macro package m
            import std.ast.*
            public macro M(input: Tokens): Tokens { input }
            public macro M(attrs: Tokens, input: Tokens): Tokens { input }
            func M(value: Int64): Int64 { value }
            "#,
            binaries: ["std.ast"]
        )
    }

    @TestCase
    func conditionalForeignBlocksGuardTheirFlattenedDeclarations(): Unit {
        let fixture = Fixture.parse(
            #"
            //- /main.cj cfg=os:Linux
            @When[os == "Windows"] foreign { func f(): Int64 }
            @When[os != "Windows"] foreign { func f(): Int64 }
            "#
        )
        let db = fixture.database()
        let errors =
            diagnostics(db, fixture.file("/main.cj").fileId)
                .filter { one => one.severity == Severity.Error }
        @Expect(errors.isEmpty())
    }

    @TestCase
    func inactiveAndOpaqueMacroInputCannotEstablishDuplicates(): Unit {
        checkDiagnostics(
            #"
            @When[os == "Windows"] func f(): Unit {}
            @When[os == "Linux"] func f(): Unit {}
            func g(): Unit {
                @When[os == "Windows"] let y = 1
                @When[os == "Linux"] let y = 2
                @Unknown let x = 1
                let x = 2
            }
            "#
        )
    }
}
