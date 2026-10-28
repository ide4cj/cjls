// ISSUE: 541
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: non-static variable 'this' cannot be referenced from a static context
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=541
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/static_this/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { public static func f(): C { this } }
//                                    ^ d0 error: non-static variable 'this' cannot be referenced from a static context
