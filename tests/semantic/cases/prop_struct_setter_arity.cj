// ISSUE: 531
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: setter can only accept 1 parameter
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/prop_struct_setter_arity/fixed/src/main.cj
// STEP: restored FROM broken
package audit
struct C { mut prop x: Int64 { get() { 1 } set(a, b) {} } }
//                                            ^^^^^^ d0 error: setter can only accept 1 parameter
