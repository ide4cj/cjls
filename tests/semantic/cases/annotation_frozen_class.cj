// ISSUE: 423
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: class cannot be modified with '@Frozen'
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: class cannot be modified with '@Frozen'
// KNOWN-MISSING: d0 issue=423
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/annotation_frozen_class/fixed/src/main.cj
// STEP: restored FROM broken
package audit
/*@s0*/@/*@/s0*/Frozen class C {}
