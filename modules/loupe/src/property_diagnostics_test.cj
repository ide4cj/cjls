package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*

@Test
class PropertyDiagnosticsTest {
    @TestCase[owner in ["class", "struct"]]
    func accessorShape(owner: String): Unit {
        // arrange / act / assert
        checkDiagnostics(
            """
            ${owner} C {
                mut prop missingSetter: Int64 { get() { 1 } }
            //  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ error: property must have accessors
                mut prop missingGetter: Int64 { set(v) {} }
            //  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ error: property must have accessors
                prop immutable: Int64 { get() { 1 } set(v) {} }
            //  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ error: immutable property cannot have setter
                prop setterOnly: Int64 { set(v) {} }
            //  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ error: immutable property cannot have setter
                prop duplicate: Int64 { get() { 1 } get() { 2 } }
            //                                      ^^^ error: duplicated 'get' in prop
                mut prop duplicateSet: Int64 { get() { 1 } set(v) {} set(w) {} }
            //                                                       ^^^ error: duplicated 'set' in prop
                prop params: Int64 { get(v) { 1 } }
            //                       ^ error: getter cannot have parameter
                mut prop arity: Int64 { get() { 1 } set(a, b) {} }
            //                                         ^^^^^^ error: setter can only accept 1 parameter
                mut prop emptySetter: Int64 { get() { 1 } set() {} }
            //                                               ^^ error: setter must contain 1 parameter
                prop empty: Int64 {}
            //  ^^^^^^^^^^^^^^^^^^^^ error: property must have accessors
            }
            """
        )
    }

    @TestCase
    func declarationContextsAllowOmittedBodies(): Unit {
        // arrange / act / assert
        checkDiagnostics(
            #"
            interface I { prop x: Int64; mut prop y: Int64 }
            abstract class A { public prop x: Int64; public mut prop y: Int64 }
            interface J { prop x: Int64 { get() { 1 } } }
            class C { mut prop x: Int64 { get() { 1 } set(v) {} } }
            struct S { prop x: Int64 { get() { 1 } } }
            "#
        )
    }
    @TestCase
    func commonPropertiesCanOmitBodies(): Unit {
        // arrange / act / assert
        checkDiagnostics(
            #"
            //- /common/main.cj module=audit package=audit
            @NonProduct
            features {}
            package audit
            public common class C {
                public common init()
                public common prop x: Int64
                public common mut prop y: Int64
                public common prop empty: Int64 {}
                public common mut prop emptyMut: Int64 {}
            }
            //- /linux/main.cj module=audit package=audit
            features {os.linux}
            package audit
            public specific class C {
                public specific init() {}
                public specific prop x: Int64 { get() { 1 } }
                public specific mut prop y: Int64 { get() { 1 } set(v) {} }
                public specific prop empty: Int64 { get() { 1 } }
                public specific mut prop emptyMut: Int64 { get() { 1 } set(v) {} }
            }
            "#
        )
    }
    @TestCase
    func malformedAccessorsRetainTheirBodyContexts(): Unit {
        // arrange / act / assert
        checkDiagnostics(
            #"
            class C {
                prop getter: Int64 { get(v) { return "wrong" } }
            //                       ^ error: getter cannot have parameter
            //                                       ^^^^^^^ error: mismatched types: expected 'Int64', found 'String'
                mut prop setter: Int64 { get() { 1 } set(v, extra) { let s: String = v } }
            //                                          ^^^^^^^^^^ error: setter can only accept 1 parameter
            //                                                                       ^ error: mismatched types: expected 'String', found 'Int64'
            }
            "#,
            binaries: ["std.core"]
        )
    }
    @TestCase
    func concreteClassesCannotOmitPropertyBodies(): Unit {
        // arrange / act / assert
        checkDiagnostics(
            #"
            class C {
                prop x: Int64
            //  ^ error: property 'x' can not be abstract
            }
            "#
        )
    }
}
