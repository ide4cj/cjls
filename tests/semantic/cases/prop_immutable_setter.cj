// ISSUE: 531
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: immutable property cannot have setter
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/prop_immutable_setter/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { prop x: Int64 { get() { 1 } set(v) {} } }
//        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ d0 error: immutable property cannot have setter
