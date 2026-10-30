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
    func customAnnotationsCheckConstructorsBeforeLocalPlacement() {
        checkDiagnostics(
            #"
            @Annotation
            public class A { const init() {} }
            @Annotation
            public class B { const init(x: Int64) {} }
            @A class C {}
            func f() {
                @A func g() {}
            //          ^ error: cannot use custom annotation
                @A let x = 1
            //         ^ error: cannot use custom annotation
                @B[1] let y = 1
            //            ^ error: cannot use custom annotation
                @B["wrong"] let badType = 1
                @B let badCount = 1
                @B[unknown] let badName = 1
                @Unknown let opaque = 1
            }
            "#
        )
    }

    @TestCase
    func customAnnotationArgumentsUseTheDeclarationsLexicalScope() {
        checkDiagnostics(
            #"
            @Annotation
            public class A { const init(x: Int64) {} }
            func f() {
                let value = 1
                @A[value] let x = 1
            //                ^ error: cannot use custom annotation
                if (true) {
                    let value = "wrong"
                    @A[value] let suppressed = 1
                }
                let A = 1
                @A[1] let (a, b) = (1, 2)
            //            ^^^^^^ error: cannot use custom annotation
                @Unknown @A[1] let nested = 1
            //                     ^^^^^^ error: cannot use custom annotation
            }
            "#
        )
    }

    @TestCase
    func customAnnotationWithInaccessibleConstructorDoesNotCheckPlacement() {
        checkDiagnostics(
            #"
            @Annotation
            public class A { private const init() {} }
            func f() { @A let x = 1 }
            "#
        )
    }

    @TestCase
    func aliasesAndGenericConstructorsRetainSuccessfulTypingRequirement() {
        checkDiagnostics(
            #"
            @Annotation public class A<T> { const init() {} }
            @Annotation public class B<T> { const init(x: T) {} }
            type Alias = B<Int64>
            func f() {
                @A let unresolved = 1
                @B[1] let inferred = 1
            //            ^^^^^^^^ error: cannot use custom annotation
                @Alias[1] let aliased = 1
            //                ^^^^^^^ error: cannot use custom annotation
            }
            "#
        )
    }

    @TestCase
    func customAnnotationsInMemberBodiesKeepTheirLocalTarget() {
        checkDiagnostics(
            #"
            @Annotation public class A { const init() {} }
            class C {
                func f() {
                    @A let x = 1
            //             ^ error: cannot use custom annotation
                    @A func g() {}
            //              ^ error: cannot use custom annotation
                }
            }
            "#
        )
    }

    @TestCase
    func supportedCustomAnnotationTargetsRemainClean() {
        checkDiagnostics(
            #"
            @Annotation public class A { const init() {} }
            @A class C {
                @A init() {}
                @A public func f(@A x: Int64): Int64 { x }
                @A public let field = 1
                @A public prop p: Int64 { get() { 1 } }
            }
            @A struct S {}
            @A interface I {}
            @A enum E { @A X }
            @A extend C {}
            @A let global = 1
            @A func f(@A x: Int64) { func g(@A y: Int64) {} }
            "#
        )
    }

    @TestCase
    func customAnnotationConstructorChangesInvalidateUneditedUses() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            //- /annotation.cj module=a package=a
            @Annotation public class A { const init(x: Int64) {} }
            //- /use.cj module=a package=a
            func f() { @A[1] let x = 1 }
            "#
                )
        let db = fixture.database()
        let use = fixture.file("/use.cj").fileId
        let definition = fixture.file("/annotation.cj").fileId
        let original = diagnostics(db, use)

        // act
        db.setFileText(definition, Rope("@Annotation public class A { const init(x: String) {} }"))
        let incompatible = diagnostics(db, use)
        db.setFileText(definition, Rope("@Annotation public class A { const init(x: Int64) {} }"))
        let restored = diagnostics(db, use)

        // assert
        @Expect(original.size, 1)
        @Expect(incompatible.isEmpty())
        @Expect(restored.size, 1)
    }

    @TestCase
    func movingCustomAnnotationSourcePreservesBodyAndUpdatesDiagnosticRange() {
        // arrange
        let text = "@Annotation public class A { const init() {} }\nfunc f() { @A let x = 1 }"
        let fixture = Fixture.parse(text)
        let db = fixture.database()
        let file = fixture.files[0].fileId
        let source = db.sourceFile(file).getOrThrow()
        let def =
            bodiesOf(db, ItemFile.Source(source))
                .filter { one => one.item(db).kind == ItemKind.Func }[0]
        let before = bodyWithSourceMap(db, def)
        let original = diagnostics(db, file)

        // act
        db.setFileText(file, Rope("\n\n" + text))
        let after = bodyWithSourceMap(db, def)
        let moved = diagnostics(db, file)

        // assert
        @Expect(before.body, after.body)
        @Expect(before.sourceMap != after.sourceMap)
        @Assert(original.size == 1 && moved.size == 1)
        @Expect(moved[0].range, TextRange(original[0].range.start + 2, original[0].range.end + 2))
    }

    @TestCase
    func multipleCustomAnnotationsReportOnePlacementErrorPerDeclaration() {
        checkDiagnostics(
            #"
            @Annotation public class A { const init() {} }
            @Annotation public class B { const init(x: Int64) {} }
            func f() {
                @A @A let x = 1
            //            ^ error: cannot use custom annotation
                @A @B[1] let y = 1
            //               ^ error: cannot use custom annotation
                @B["wrong"] @A let z = 1
            //                     ^ error: cannot use custom annotation
            }
            "#
        )
    }

    @TestCase
    func wildcardAnnotationsHaveAPlacementTargetWithoutBindings() {
        checkDiagnostics(
            #"
            @Annotation public class A { const init(x: Int64) {} }
            func f() {
                @A[1] let _ = 1
            //            ^ error: cannot use custom annotation
                @A[1] let (_, _) = (1, 2)
            //            ^^^^^^ error: cannot use custom annotation
            }
            "#
        )
    }

    @TestCase
    func mainRejectsTheFirstAnnotationBeforeResolvingItsName() {
        checkDiagnostics(
            #"
              @Unknown[1] main() { 0 }
            //^^^^^^^^^^^ error: unexpected annotation '@Unknown' on main
            "#
        )
        checkDiagnostics(
            #"
              @First @Other main() { 0 }
            //^^^^^^ error: unexpected annotation '@First' on main
            "#
        )
        checkDiagnostics(
            #"
              @Frozen @First main() { 0 }
            //^^^^^^^ error: unexpected annotation '@Frozen' on main
            "#
        )
        checkDiagnostics(
            #"
              @C main() { 0 }
            //^ error: main cannot be modified with '@C'
            "#
        )
    }

    @TestCase[name in ["OverflowThrowing", "OverflowWrapping", "OverflowSaturating"]]
    func overflowAnnotationsRemainValidOnMain(name: String) {
        checkDiagnostics("@${name} main(): Int64 { 0 }")
    }

    @TestCase
    func nativeMainChecksPreserveParserOrderAndDeprecationMessage() {
        checkDiagnostics(
            #"
              @OverflowWrapping @Frozen main() { 0 }
            //^^^^^^^^^^^^^^^^^ error: unexpected annotation '@OverflowWrapping' on main
            "#
        )
        checkDiagnostics(
            #"
              @Deprecated main() { 0 }
            //^^^^^^^^^^^ error: main can not be target of @Deprecated
            "#
        )
        checkDiagnostics(
            #"
            //- /main.cj cfg=os:Linux
              @When[os == "Windows"] @Frozen main() { 0 }
            //^^^^^^^^^^^^^^^^^^^^^^ error: unexpected annotation '@When' on main
            //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ hint: code is inactive due to @When: os is "Linux"
            "#
        )
    }

    @TestCase
    func mainInputOfAResolvedMacroRemainsOpaque() {
        // arrange
        let text = "import m.ms.*\n@M[x] main() { 0 }\n"
        let (db, file) = expansionDatabase(text)
        let pending = diagnostics(db, file.fileId(db))

        // act
        answer(db, file, "M", "main() { 0 }", [])
        let expanded = diagnostics(db, file.fileId(db))
        answer(db, file, "M", "@Frozen main() { 0 }", [])
        let generated = diagnostics(db, file.fileId(db))
        db.setFileText(file.fileId(db), Rope(text.replace("@M[x]", "@M[y]")))
        let stale = diagnostics(db, file.fileId(db))

        // assert
        @Expect(pending.isEmpty())
        @Expect(expanded.isEmpty())
        @Assert(generated.size == 1)
        @Expect(generated[0].message, "unexpected annotation '@Frozen' on main")
        let start = text.indexOf("@M[x]").getOrThrow()
        @Expect(generated[0].range, TextRange(start, start + 5))
        @Expect(stale.isEmpty())
    }

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
    func customAnnotationFromBodyMacroMapsToItsCallAndIgnoresStaleOutput() {
        let text =
            "import m.ms.*\n@Annotation public class Mark { const init() {} }\nfunc f() { @A() }\n"
        let (db, file) = expansionDatabase(text)
        answer(db, file, "A", "@Mark let value = 1", [])
        let result = diagnostics(db, file.fileId(db))
        @Assert(result.size == 1)
        @Expect(result[0].message, "cannot use custom annotation")
        let start = text.indexOf("@A()").getOrThrow()
        @Expect(result[0].range, TextRange(start, start + 2))
        db.setFileText(file.fileId(db), Rope(text.replace("@A()", "@A(1)")))
        @Expect(diagnostics(db, file.fileId(db)).isEmpty())
    }

    @TestCase
    func opaqueBodyMacroInputDoesNotValidateCustomAnnotations() {
        let (db, file) =
            expansionDatabase(
                "import m.ms.*\n@Annotation public class Mark { const init() {} }\nfunc f() { @M[x] @Mark let value = 1 }\n"
            )
        @Expect(diagnostics(db, file.fileId(db)).isEmpty())
        answer(db, file, "M", "let value = 1", [])
        @Expect(diagnostics(db, file.fileId(db)).isEmpty())
    }

    @TestCase
    func opaqueEnclosingMacroDoesNotValidateCustomAnnotationInput() {
        let (db, file) =
            expansionDatabase(
                "import m.ms.*\n@Annotation public class Mark { const init() {} }\n@M[x] func f() { @Mark let value = 1 }\n"
            )
        @Expect(diagnostics(db, file.fileId(db)).isEmpty())
        answer(db, file, "M", "func f() {}", [])
        @Expect(diagnostics(db, file.fileId(db)).isEmpty())
    }

    @TestCase
    func inactiveCustomAnnotationDoesNotCheckPlacement() {
        checkDiagnostics(
            #"
            //- /main.cj cfg=test:false
            @Annotation
            public class A { const init() {} }
            func f() {
                @When[test] @A let x = 1
            //  ^^^^^^^^^^^^^^^^^^^^^^^^ hint: code is inactive due to @When: test is not set
            }
            "#
        )
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
