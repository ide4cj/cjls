// ISSUE: 531
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: expected 'get' or 'set' in prop body, found 'foo'
// CJC: audit error: unclosed delimiter: '{'
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=531
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/prop_accessor_name/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { prop x: Int64 { foo() { 1 } } }
//                        ^^^ d0 error: expected 'get' or 'set' in prop body, found 'foo'
