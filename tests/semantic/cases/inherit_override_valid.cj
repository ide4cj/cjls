// ISSUE: 538
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
package audit
open class B { public open func f(): Int64 { 1 } }; class C <: B { public override func f(): Int64 { 2 } }
