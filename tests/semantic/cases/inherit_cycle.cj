// ISSUE: 538
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: inheritance cycle detected: 'A->B->A'
// CJC: audit error: recursive constructor calling detected
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=538
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/inherit_cycle/fixed/src/main.cj
// STEP: restored FROM broken
  package audit
  open class A <: B {}; open class B <: A {}
//^ d0 error: inheritance cycle detected: 'A->B->A'
