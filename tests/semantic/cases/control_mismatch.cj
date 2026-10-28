// ISSUE: 544
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: mismatched types
// SOURCE: src/main.cj %f
// KNOWN-EXTRA: extra_body issue=544
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/control_mismatch/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(): Int64 { "wrong" }
//                ^^^^^^^ d0 error: mismatched types: expected 'Int64', found 'String'
//              ^^^^^^^^^^^ extra_body error: mismatched types: expected 'Int64', found 'String'
