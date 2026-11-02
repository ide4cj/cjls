// ISSUE: 539
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: function 'x' has overload conflicts
// CJC: audit error: function 'x' has overload conflicts
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=539
// KNOWN-MISSING: d1 issue=539
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/duplicate_method_method/fixed.cj
// STEP: restored FROM broken
package audit
class C0 { func x(): Int64 { 1 }; func x(): Int64 { 1 } }
//                                     ^ d0 error: function 'x' has overload conflicts
struct S0 { func x(): Int64 { 1 }; func x(): Int64 { 1 } }
//                                      ^ d1 error: function 'x' has overload conflicts
