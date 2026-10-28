// ISSUE: 530
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: recursive constructor calling detected
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: recursive constructor calling detected
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/field_delegation_cycle/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { /*@s0*/init/*@/s0*/() { this(1) }; init(x: Int64) { this() } }
