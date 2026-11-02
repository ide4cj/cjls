// ISSUE: 539
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: function 'f' has overload conflicts
// SOURCE: src/main.cj %f
// KNOWN-MISSING: conflict issue=539
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/generic_arity_unused_conflict/fixed.cj
// STEP: restored FROM broken
package audit
func f<T>(): Unit {}
func f<T, U>(): Unit {}
//   ^ conflict error: function 'f' has overload conflicts
