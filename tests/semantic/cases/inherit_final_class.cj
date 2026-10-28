// ISSUE: 538
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: super class 'B' is not inheritable
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: super class 'B' is not inheritable
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/inherit_final_class/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class B {}; class C <: /*@s0*/B/*@/s0*/ {}
