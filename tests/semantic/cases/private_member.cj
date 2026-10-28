// ISSUE: 541
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: can not access field 'x'
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: can not access field 'x'
// KNOWN-MISSING: d0 issue=541
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/private_member/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { private let x = 1 }; func f(c: C): Int64 { /*@s0*/c/*@/s0*/.x }
