// ISSUE: 531
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: duplicated 'get' in prop
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: duplicated 'get' in prop
// KNOWN-MISSING: d0 issue=531
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/prop_duplicate_getter/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { prop x: Int64 { get() { 1 } /*@s0*/get/*@/s0*/() { 2 } } }
