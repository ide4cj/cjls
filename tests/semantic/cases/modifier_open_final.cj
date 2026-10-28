// ISSUE: 423
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: expected declaration, found 'final'
// CJC: audit error: expected ';' or '<NL>', found keyword 'class'
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: expected a declaration
// EXPECT: d1 s1 error: expected a newline or ';'
// EXPECT: d2 s2 error: expected a declaration
// EXPECT: d3 s3 error: expected a newline or ';'
// EXPECT: d4 s4 error: expected a declaration
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/modifier_open_final/fixed/src/main.cj
// STEP: restored FROM broken
package audit
open/*@s0*//*@/s0*//*@s1*//*@/s1*/ /*@s2*//*@/s2*/final class C {/*@s3*//*@/s3*//*@s4*//*@/s4*/}
