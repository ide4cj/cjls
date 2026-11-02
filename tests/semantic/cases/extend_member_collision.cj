// ISSUE: 539
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: extend member 'f' is not allowed to shadow members of 'extend C'
// CJC: audit error: extend member 'f' is not allowed to shadow members of 'extend C'
// SOURCE: src/main.cj %f
// KNOWN-MISSING: first issue=539
// KNOWN-MISSING: second issue=539
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/extend_member_collision/fixed.cj
// STEP: restored FROM broken
package audit
class C {}
extend C {
    func f(): Unit {}
//       ^ first error: extend member 'f' is not allowed to shadow members of 'extend C'
}
extend C {
    func f(): Unit {}
//       ^ second error: extend member 'f' is not allowed to shadow members of 'extend C'
}
