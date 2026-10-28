// ISSUE: 531
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: property must have accessors
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: property must have accessors
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/prop_missing_getter/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { /*@s0*/mut prop x: Int64 { set(v) {} }/*@/s0*/ }
