// ISSUE: 423
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
package audit
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
