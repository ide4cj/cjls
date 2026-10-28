// ISSUE: 529
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: cannot assign to immutable value
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=529
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/field_double_init/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { let x: Int64; init() { x = 1; x = 2 } }
//                                      ^^^^^ d0 error: cannot assign to immutable value
