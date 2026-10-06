package loupe

import std.unittest.*
import std.unittest.testmacro.*

/**
 * Which `extend`s a member lookup sees (step 7b of #48): those of the body's package, those of the
 * type's, and those of another package through an interface the file imports.
 */
@Test
class ExtendDefinitionTest {
    @TestCase
    func anExtendOfTheBodysPackageOfATypeOfAnother() {
        // N81
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /main.cj module=m package=m
            package m
            import m.a.C
            extend C {
                static func e(): Int64 { 1 }
            //              ^ def
            }
            func g(): Int64 { C.$0e() }
            "#)
    }

    @TestCase
    func anExtendOfTheTypesPackageInAFileImportingNothingElse() {
        // N81
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /a/ext.cj module=m package=m.a
            package m.a
            extend C {
                public static func e(): Int64 { 1 }
            //                     ^ def
            }
            //- /main.cj module=m package=m
            package m
            import m.a.C
            func g(): Int64 { C.$0e() }
            "#)
    }

    @TestCase
    func anExtendOfNoInterfaceOfAThirdPackageIsNotSeen() {
        // N81
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /b/b.cj module=m package=m.b
            package m.b
            import m.a.C
            extend C {
                public static func e(): Int64 { 1 }
            }
            public func unused(): Unit {}
            //- /main.cj module=m package=m
            package m
            import m.a.C
            import m.b.*
            func g(): Int64 { C.$0e() }
            //                  ^ no definition
            "#)
    }

    @TestCase
    func anExtendOfNoInterfaceOfATypeOfTheLanguageIsSeenInItsPackage() {
        // N81
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            extend Int64 {
                public static func seven(): Int64 { 7 }
            //                     ^^^^^ def
            }
            func g(): Int64 { Int64.$0seven() }
            "#)
    }

    @TestCase
    func anExtendOfNoInterfaceOfATypeOfTheLanguageIsNotSeenOutsideItsPackage() {
        // N81: cjc's "undeclared identifier 'seven'", a glob of its package or not; only `std.core`'s
        // are seen everywhere (N84)
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            extend Int64 {
                public static func seven(): Int64 { 7 }
            }
            public func unused(): Unit {}
            //- /main.cj module=m package=m
            package m
            import m.a.*
            func g(): Int64 { Int64.$0seven() }
            //                        ^^^^^ no definition
            "#)
    }

    @TestCase
    func anExtendOfAnInterfacesPackageThroughTheInterfaceImported() {
        // N82
        // the interface's `e` too: an implementation is not told from what it implements (step 8)
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /i/i.cj module=m package=m.i
            package m.i
            import m.a.C
            public interface I {
                static func e(): Int64
            //              ^ def
            }
            extend C <: I {
                public static func e(): Int64 { 1 }
            //                     ^ def
            }
            //- /main.cj module=m package=m
            package m
            import m.a.C
            import m.i.I
            func g(): Int64 { C.$0e() }
            "#)
    }

    @TestCase
    func anExtendOfAnInterfacesPackageThroughAGlob() {
        // N82
        // the interface's `e` too: an implementation is not told from what it implements (step 8)
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /i/i.cj module=m package=m.i
            package m.i
            import m.a.C
            public interface I {
                static func e(): Int64
            //              ^ def
            }
            extend C <: I {
                public static func e(): Int64 { 1 }
            //                     ^ def
            }
            //- /main.cj module=m package=m
            package m
            import m.a.C
            import m.i.*
            func g(): Int64 { C.$0e() }
            "#)
    }

    @TestCase
    func anExtendOfAnInterfacesPackageThroughAnAlias() {
        // N82
        // the interface's `e` too: an implementation is not told from what it implements (step 8)
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /i/i.cj module=m package=m.i
            package m.i
            import m.a.C
            public interface I {
                static func e(): Int64
            //              ^ def
            }
            extend C <: I {
                public static func e(): Int64 { 1 }
            //                     ^ def
            }
            //- /main.cj module=m package=m
            package m
            import m.a.C
            import m.i.I as J
            func g(): Int64 { C.$0e() }
            "#)
    }

    @TestCase
    func anExtendOfAnInterfacesPackageThroughAPublicImportOfAnotherFile() {
        // N82: a re-export is seen in every file of the package (N11)
        // the interface's `e` too: an implementation is not told from what it implements (step 8)
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /i/i.cj module=m package=m.i
            package m.i
            import m.a.C
            public interface I {
                static func e(): Int64
            //              ^ def
            }
            extend C <: I {
                public static func e(): Int64 { 1 }
            //                     ^ def
            }
            //- /reexport.cj module=m package=m
            package m
            public import m.i.I
            //- /main.cj module=m package=m
            package m
            import m.a.C
            func g(): Int64 { C.$0e() }
            "#)
    }

    @TestCase
    func anExtendOfAnInterfacesPackageIsNotSeenThroughAnotherFilesImport() {
        // N82
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /i/i.cj module=m package=m.i
            package m.i
            import m.a.C
            public interface I {
                static func e(): Int64
            }
            extend C <: I {
                public static func e(): Int64 { 1 }
            }
            //- /other.cj module=m package=m
            package m
            import m.i.I
            //- /main.cj module=m package=m
            package m
            import m.a.C
            func g(): Int64 { C.$0e() }
            //                  ^ no definition
            "#)
    }

    @TestCase
    func anExtendOfAnInterfacesPackageIsNotSeenWithoutTheInterface() {
        // N82: another name of the interface's package is not enough
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /i/i.cj module=m package=m.i
            package m.i
            import m.a.C
            public interface I {
                static func e(): Int64
            }
            extend C <: I {
                public static func e(): Int64 { 1 }
            }
            public func other(): Unit {}
            //- /main.cj module=m package=m
            package m
            import m.a.C
            import m.i.other
            func g(): Int64 { C.$0e() }
            //                  ^ no definition
            "#)
    }

    @TestCase
    func anExtendOfAnInterfacesPackageIsNotSeenThroughASuperInterface() {
        // N82: the interfaces it lists, not those they inherit
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /i/i.cj module=m package=m.i
            package m.i
            import m.a.C
            public interface I {}
            public interface J <: I {
                static func e(): Int64
            }
            extend C <: J {
                public static func e(): Int64 { 1 }
            }
            //- /main.cj module=m package=m
            package m
            import m.a.C
            import m.i.I
            func g(): Int64 { C.$0e() }
            //                  ^ no definition
            "#)
    }


    @TestCase
    func aMemberOfNoInterfaceOfAnExtendSeenThroughOneIsFound() {
        // N82, N80: cjc finds it, then says it "is not a member": only its interfaces' members are
        // accessible, which is checked after the lookup
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /i/i.cj module=m package=m.i
            package m.i
            import m.a.C
            public interface I {}
            extend C <: I {
                public static func other(): Int64 { 1 }
            //                     ^^^^^ def
            }
            //- /main.cj module=m package=m
            package m
            import m.a.C
            import m.i.I
            func g(): Int64 { C.$0other() }
            "#)
    }

    @TestCase
    func aDefaultMemberOfAnInterfaceAnExtendBrings() {
        // N82: default ones included
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /i/i.cj module=m package=m.i
            package m.i
            import m.a.C
            public interface I {
                static func e(): Int64 { 1 }
            //              ^ def
            }
            extend C <: I {}
            //- /main.cj module=m package=m
            package m
            import m.a.C
            import m.i.I
            func g(): Int64 { C.$0e() }
            "#)
    }

    @TestCase
    func anExtendSeenThroughASealedInterfaceAGlobImports() {
        // N82, N87: `sealed` is `public`, a glob brings it to a package `internal` does not reach
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /i/i.cj module=m package=m.i
            package m.i
            import m.a.C
            sealed interface I {
                static func e(): Int64 { 1 }
            //              ^ def
            }
            extend C <: I {}
            //- /main.cj module=m package=m
            package m
            import m.a.C
            import m.i.*
            func g(): Int64 { C.$0e() }
            "#)
    }

    @TestCase
    func anExtendOfASuperclassSeenThroughAnInterfaceByThis() {
        // N82, N79: `this` sees the extends of its supertypes the file sees
        // the interface's `e` too: an implementation is not told from what it implements (step 8)
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public open class C {}
            //- /i/i.cj module=m package=m.i
            package m.i
            import m.a.C
            public interface I {
                func e(): Int64
            //       ^ def
            }
            extend C <: I {
                public func e(): Int64 { 1 }
            //              ^ def
            }
            //- /main.cj module=m package=m
            package m
            import m.a.C
            import m.i.I
            class D <: C {
                func g(): Int64 { this.$0e() }
            }
            "#)
    }
}
