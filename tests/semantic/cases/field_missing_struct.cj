// ISSUE: 529
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: the uninitialized member variable 'x' is not initialized in the constructor of class or struct
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=529
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/field_missing_struct/fixed/src/main.cj
// STEP: restored FROM broken
package audit
struct C { let x: Int64; init() {} }
//                       ^ d0 error: the uninitialized member variable 'x' is not initialized in the constructor of class or struct
