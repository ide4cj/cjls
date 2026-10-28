// ISSUE: 531
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: expected 'get' or 'set' in prop body, found 'foo'
// CJC: audit error: unclosed delimiter: '{'
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: expected 'get' or 'set' in prop body, found 'foo'
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/prop_accessor_name/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { prop x: Int64 { /*@s0*/foo/*@/s0*/() { 1 } } }
