// ISSUE: 530
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: call to 'super' must be first expression in constructor of class 'C'
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: call to 'super' must be first expression in constructor of class 'C'
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/field_super_late/fixed/src/main.cj
// STEP: restored FROM broken
package audit
open class B { init() {} }; class C <: B { init() { println(1); /*@s0*/s/*@/s0*/uper() } }
