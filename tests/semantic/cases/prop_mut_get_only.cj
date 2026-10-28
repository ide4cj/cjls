// ISSUE: 531
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: property must have accessors
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=531
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/prop_mut_get_only/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { mut prop x: Int64 { get() { 1 } } }
//        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ d0 error: property must have accessors
