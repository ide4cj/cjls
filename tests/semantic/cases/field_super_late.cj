// ISSUE: 530
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: call to 'super' must be first expression in constructor of class 'C'
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=530
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/field_super_late/fixed/src/main.cj
// STEP: restored FROM broken
package audit
open class B { init() {} }; class C <: B { init() { println(1); super() } }
//                                                              ^ d0 error: call to 'super' must be first expression in constructor of class 'C'
