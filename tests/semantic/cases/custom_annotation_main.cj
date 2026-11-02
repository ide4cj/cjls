// ISSUE: 423
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: unexpected annotation '@Unknown' on main
// SOURCE: src/main.cj %f
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/declaration_validation/custom_main_fixed.cj
// STEP: restored FROM broken
package audit
  @Unknown[1] main() { 0 }
//^^^^^^^^^^^ invalid_main error: unexpected annotation '@Unknown' on main
