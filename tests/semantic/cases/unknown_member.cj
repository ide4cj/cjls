// ISSUE: 541
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: 'missing' is not a member of class 'C'
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: 'missing' is not a member of class 'C'
// KNOWN-MISSING: d0 issue=541
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/unknown_member/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C {}; func f(c: C): Unit { c./*@s0*/missing/*@/s0*/() }
