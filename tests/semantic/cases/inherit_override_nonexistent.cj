// ISSUE: 538
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: 'override' function 'f' does not have an overridden function in its supertype
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/inherit_override_nonexistent/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { public override func f(): Int64 { 1 } }
//        ^ d0 error: 'override' function 'f' does not have an overridden function in its supertype
