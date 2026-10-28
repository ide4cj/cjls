// ISSUE: 538
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
package audit
interface I { func f(): Int64 }; class C <: I { public func f(): Int64 { 1 } }
