// ISSUE: 528
// PACKAGE: audit .
// STEP: control
// CJC: audit warning: magnitude of floating-point literal too large for type 'Float32', maximum is 3.40282347E38
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
package audit
func f(): Float32 { 1e100f32 }
