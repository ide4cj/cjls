// ISSUE: 539
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: redefinition of declaration 'x'
// CJC: audit error: redefinition of declaration 'x'
// CJC: audit error: redefinition of declaration 'x'
// CJC: audit error: redefinition of declaration 'x'
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=539
// KNOWN-MISSING: d1 issue=539
// KNOWN-MISSING: d2 issue=539
// KNOWN-MISSING: d3 issue=539
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/duplicate_field_method/fixed.cj
// STEP: restored FROM broken
package audit
class C0 { let x = 1; func x(): Int64 { 1 } }
//                         ^ d0 error: redefinition of declaration 'x'
class C1 { func x(): Int64 { 1 }; let x = 1 }
//                                    ^ d1 error: redefinition of declaration 'x'
struct S0 { let x = 1; func x(): Int64 { 1 } }
//                          ^ d2 error: redefinition of declaration 'x'
struct S1 { func x(): Int64 { 1 }; let x = 1 }
//                                     ^ d3 error: redefinition of declaration 'x'
