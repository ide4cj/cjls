// ISSUE: 531
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: setter can only accept 1 parameter
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=531
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/prop_setter_arity/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { mut prop x: Int64 { get() { 1 } set(a, b) {} } }
//                                           ^^^^^^ d0 error: setter can only accept 1 parameter
