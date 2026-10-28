// ISSUE: 529
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: the uninitialized member variable 'x' is not initialized in the constructor of class or struct
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: the uninitialized member variable 'x' is not initialized in the constructor of class or struct
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/field_branch_missing/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { let x: Int64; /*@s0*/i/*@/s0*/nit(b: Bool) { if (b) { x = 1 } } }
