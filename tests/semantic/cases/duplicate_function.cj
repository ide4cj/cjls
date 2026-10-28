// ISSUE: 539
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: function 'f' has overload conflicts
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=539
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/duplicate_function/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(): Int64 { 1 }; func f(): Int64 { 2 }
//                          ^ d0 error: function 'f' has overload conflicts
