package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*
import loupe.hir.*
import ginkgo.TextRange
import rope.Rope

@Test
class DeclarationDiagnosticsTest {
    @TestCase
    func annotationTargetsKeepCompilerPointRanges() {
        checkDiagnostics(
            #"
              @Frozen class C {}
            //^ error: class cannot be modified with '@Frozen'
              @Frozen struct S {}
            //^ error: struct cannot be modified with '@Frozen'
              @Frozen let x = 1
            //^ error: variable cannot be modified with '@Frozen'
              @C class D {}
            //^ error: class cannot be modified with '@C'
              @FastNative func f() {}
            //^ error: non-foreign function cannot be modified with '@FastNative'
              @CallingConv[CDECL] func g() {}
            //^^^^^^^^^^^^^^^^^^^ error: only CFunc can use '@CallingConv'
            "#
        )
    }

    @TestCase
    func annotationScopesDistinguishMembersAndLocals() {
        checkDiagnostics(
            #"
            class C {
                @C func f() {}
            //  ^^ error: '@C' can only be used in top-level scope
            }
            func f() {
                @Frozen func g() {}
            //  ^ error: local function cannot be modified with '@Frozen'
            }
            "#
        )
    }

    @TestCase
    func supportedAnnotationTargetsRemainClean() {
        checkDiagnostics(
            #"
            @Frozen func f() {}
            @C struct S {}
            @C func g() {}
            class C {
                @Frozen init() {}
                @Frozen public func f() {}
                @Frozen prop p: Int64 { get() { 1 } }
            }
            foreign {
                @FastNative func native(): Unit
                @CallingConv[CDECL] func other(): Unit
            }
            "#
        )
    }

    @TestCase
    func abstractAndOpenMembersNeedInheritedVisibility() {
        checkDiagnostics(
            #"
            abstract class C {
                private func f(): Unit
            //               ^ error: the visibility of an 'abstract' function must be 'public' or 'protected'
                prop p: Int64
            //       ^ error: the visibility of an 'abstract' property must be 'public' or 'protected'
                public func good(): Unit
                protected prop goodProp: Int64
            }
            open class D {
                open func f() {}
            //            ^ error: the visibility of an 'open' function must be 'public' or 'protected'
                public open func good() {}
            }
              sealed class E {}
            //             ^ error: non-abstract class cannot be modified by 'sealed'
            "#
        )
    }

    @TestCase
    func inactiveDeclarationsAreNotChecked() {
        checkDiagnostics(
            #"
            //- /main.cj cfg=test:false
               @When[test] @Frozen class C {}
            // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ hint: code is inactive due to @When: test is not set
            "#
        )
    }
    @TestCase
    func aGeneratedInvalidAnnotationIsMappedToItsMacroHead() {
        // arrange
        let (db, file) = expansionDatabase("import m.ms.*\n@M[x] class C {}\n")
        answer(db, file, "M", "@Frozen class C {}", [])
        // act
        let result = diagnostics(db, file.fileId(db))
        // assert
        @Expect(result.size, 1)
        @Expect(result[0].message, "class cannot be modified with '@Frozen'")
        @Expect(result[0].range, TextRange(14, 19))
    }

    @TestCase
    func aMacroReplacementOwnsItsDeclarationChecks() {
        // arrange
        let (db, file) = expansionDatabase("import m.ms.*\n@M[x] @Frozen class C {}\n")
        answer(db, file, "M", "class C {}", [])
        // act
        let result = diagnostics(db, file.fileId(db))

        // assert
        @Expect(result.isEmpty())
    }

    @TestCase
    func modifierConflictsUseTheLaterModifier() {
        checkDiagnostics(
            #"
            open class C {
                private open func f() {}
            //          ^^^^ error: 'open' and 'private' modifiers conflict on function declaration
                open internal prop p: Int64 { get() { 1 } }
            //       ^^^^^^^^ error: 'internal' and 'open' modifiers conflict on property declaration
            }
              public private class D {}
            //       ^^^^^^^ error: 'private' and 'public' modifiers conflict on class declaration
            "#
        )
    }

    @TestCase
    func builtinAnnotationArgumentsFollowTheirCompilerContracts() {
        checkDiagnostics(
            #"
              @Frozen[1] func f() {}
            //        ^ error: '@Frozen' should have no arg
              @C[1] struct S {}
            //   ^ error: '@C' should have no arg
              @C func generic<T>() {}
            //               ^ error: CFunc cannot have type parameters
            foreign {
                @CallingConv func missing(): Unit
            //  ^^^^^^^^^^^^ error: '@CallingConv' should have one arg
                @CallingConv[WRONG] func g(): Unit
            //  ^^^^^^^^^^^^^^^^^^^ error: '@CallingConv' have not supported 'WRONG' yet
                @CallingConv[1] func h(): Unit
            //  ^^^^^^^^^^^^^^^ error: '@CallingConv' arg should be right type
            }
            "#
        )
    }

    @TestCase
    func staleMacroOutputsDoNotPublishDeclarationErrors() {
        // arrange
        let (db, file) = expansionDatabase("import m.ms.*\n@M[x] class C {}\n")
        answer(db, file, "M", "@Frozen class C {}", [])
        db.setFileText(file.fileId(db), Rope("import m.ms.*\n@M[y] class C {}\n"))
        // act
        let result = diagnostics(db, file.fileId(db))

        // assert
        @Expect(result.isEmpty())
    }

    @TestCase
    func invalidAbstractMembersAndGenericOperatorsKeepCompilerPoints() {
        checkDiagnostics(
            #"
            abstract class C {
                public static func f(): Unit
            //  ^ error: function 'f' can not be abstract
            }
            struct S {
                public operator func +<T>(x: T): S { S() }
            //  ^ error: generic is not allowed in operator overload function
            }
            "#
        )
    }
    @TestCase
    func constructorKindsAndParameterTargetsAreDistinct() {
        checkDiagnostics(
            #"
            enum E { @Frozen A(Int64) | @Frozen B }
            //                          ^ error: variable cannot be modified with '@Frozen'
            class C {
                @Frozen C() {}
                @Frozen ~init() {}
            }
            func f(@Frozen x: Int64) {}
            //     ^ error: parameter cannot be modified with '@Frozen'
              @Frozen[1] main(): Int64 { 0 }
            //^^^^^^^^^^ error: unexpected annotation '@Frozen' on main
            "#
        )
    }
    @TestCase
    func finalizersAndExtendMutabilityKeepTheirDeclarationContexts() {
        checkDiagnostics(
            #"
            open class C { ~init() {} }
            //             ^ error: finalizer is forbidden in class 'C' that is open
            abstract class D { ~init() {} }
            //                 ^ error: finalizer is forbidden in class 'D' that is abstract
            sealed abstract class E { ~init() {} }
            //                        ^ error: finalizer is forbidden in class 'E' that is open
            extend C { public mut func f() {} }
            //                ^^^ error: 'mut' modifier is illegal in extend body of 'C'
            extend Int64 { public mut func f() {} }
            //                    ^^^ error: 'mut' modifier is illegal in extend body of 'Int64'
            struct S { var x = 0 }
            extend S { public mut func f() { this.x = 1 } }
            "#
        )
    }

    @TestCase
    func unreadMemberMacrosDoNotValidateTheirOpaqueInput() {
        // arrange
        let (db, file) = expansionDatabase("import m.ms.*\nclass C { @M[x] @C func f() {} }\n")
        answer(db, file, "M", "func f() {}", [])

        // act
        let result = diagnostics(db, file.fileId(db))

        // assert
        @Expect(result.isEmpty())
    }

    @TestCase
    func bodyMacroOutputUsesLocalAnnotationTargets() {
        // arrange
        let (db, file) = expansionDatabase("import m.ms.*\nfunc f() { @A() }\n")
        answer(db, file, "A", "@Frozen func bad() {}", [])

        // act
        let result = diagnostics(db, file.fileId(db))

        // assert
        @Expect(result.size, 1)
        @Expect(result[0].message, "local function cannot be modified with '@Frozen'")
    }
    @TestCase
    func commonAbstractMembersNeedAnExplicitRoleAndCannotImplementAbstractBodies() {
        checkDiagnostics(
            #"
            //- /common/main.cj module=probe package=probe
            @NonProduct
            features {}
            package probe
            public common abstract class C {
                public common init()
                public abstract func f(): Unit {}
            //  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ error: abstract function can not have body
                public abstract prop p: Int64 { get() { 1 } }
            //  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ error: abstract property can not have body
                public func g(): Unit
            //              ^ error: 'common' abstract class function must have explicit 'common' or 'abstract' modifier
            }
            //- /linux/main.cj module=probe package=probe
            features {os.linux}
            package probe
            public specific abstract class C {
                public specific init() {}
            }
            "#
        )
    }
}
