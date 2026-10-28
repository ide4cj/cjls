// ISSUE: 538
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: 'override' function 'f' does not have an overridden function in its supertype
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: 'override' function 'f' does not have an overridden function in its supertype
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/inherit_override_nonexistent/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { /*@s0*/p/*@/s0*/ublic override func f(): Int64 { 1 } }
