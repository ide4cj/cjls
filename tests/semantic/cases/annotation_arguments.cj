// ISSUE: 423
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: '@Frozen' should have no arg
// CJC: audit error: '@C' should have no arg
// CJC: audit error: CFunc cannot have type parameters
// CJC: audit error: '@CallingConv' should have one arg
// CJC: audit error: '@CallingConv' have not supported 'WRONG' yet
// CJC: audit error: '@CallingConv' arg should be right type
// SOURCE: src/main.cj %f
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/declaration_validation/arguments_fixed.cj
// STEP: restored FROM broken
  package audit
  @Frozen[1] func f() {}
//        ^ frozen_arg error: '@Frozen' should have no arg
  @C[1] struct S {}
//   ^ c_arg error: '@C' should have no arg
  @C func generic<T>() {}
//               ^ c_generic error: CFunc cannot have type parameters
  foreign {
      @CallingConv func missing(): Unit
//    ^^^^^^^^^^^^ calling_missing error: '@CallingConv' should have one arg
      @CallingConv[WRONG] func g(): Unit
//    ^^^^^^^^^^^^^^^^^^^ calling_name error: '@CallingConv' have not supported 'WRONG' yet
      @CallingConv[1] func h(): Unit
//    ^^^^^^^^^^^^^^^ calling_type error: '@CallingConv' arg should be right type
  }
