// ISSUE: 532
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: cannot assign to immutable value
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: cannot assign to immutable value
// KNOWN-MISSING: d0 issue=532
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/write_let_field/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { let x = 1; func f(): Unit { /*@s0*/x = 2/*@/s0*/ } }
