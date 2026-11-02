// ISSUE: 531
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: getter cannot have parameter
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/prop_getter_params/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { prop x: Int64 { get(v) { 1 } } }
//                        ^ d0 error: getter cannot have parameter
