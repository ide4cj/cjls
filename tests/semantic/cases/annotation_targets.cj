// ISSUE: 423
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: struct cannot be modified with '@Frozen'
// CJC: audit error: variable cannot be modified with '@Frozen'
// CJC: audit error: class cannot be modified with '@C'
// CJC: audit error: non-foreign function cannot be modified with '@FastNative'
// CJC: audit error: only CFunc can use '@CallingConv'
// SOURCE: src/main.cj %f
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/declaration_validation/annotation_targets_fixed.cj
// STEP: restored FROM broken
  package audit
  @Frozen struct S {}
//^ frozen_struct error: struct cannot be modified with '@Frozen'
  @Frozen let x = 1
//^ frozen_variable error: variable cannot be modified with '@Frozen'
  @C class C {}
//^ c_class error: class cannot be modified with '@C'
  @FastNative func f() {}
//^ fast_function error: non-foreign function cannot be modified with '@FastNative'
  @CallingConv[CDECL] func g() {}
//^^^^^^^^^^^^^^^^^^^ calling_function error: only CFunc can use '@CallingConv'
