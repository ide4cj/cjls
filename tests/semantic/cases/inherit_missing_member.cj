// ISSUE: 538
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: class 'C' missing abstract modifier, otherwise abstract function or property should be implemented
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: class 'C' missing abstract modifier, otherwise abstract function or property should be implemented
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/inherit_missing_member/fixed/src/main.cj
// STEP: restored FROM broken
package audit
interface I { func f(): Int64 }; /*@s0*/class C <: I {}/*@/s0*/
