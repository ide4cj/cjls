// ISSUE: 423
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: expected declaration, found 'final'
// CJC: audit error: expected ';' or '<NL>', found keyword 'class'
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/modifier_open_final/fixed/src/main.cj
// STEP: restored FROM broken
package audit
open final class C {}
//  | d0 error: expected a declaration
//  | d1 error: expected a newline or ';'
//   | d2 error: expected a declaration
//                  | d3 error: expected a newline or ';'
//                  | d4 error: expected a declaration
