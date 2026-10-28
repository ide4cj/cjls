// ISSUE: 530
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: there is no non-parameter constructor in super class, please invoke super call explicitly
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: there is no non-parameter constructor in super class, please invoke super call explicitly
// KNOWN-MISSING: d0 issue=530
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/field_super_missing/fixed/src/main.cj
// STEP: restored FROM broken
package audit
open class B { init(x: Int64) {} }; class C <: B { /*@s0*/init/*@/s0*/() {} }
