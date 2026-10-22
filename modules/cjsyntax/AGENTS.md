# Working on cjsyntax

Read [the grammar and tree constraints](README.md) before changing syntax.

- Check grammar changes against the compiler parser and add focused parser
  regressions, including incomplete-input recovery where relevant. Record any
  compiler-oracle comparison and its SDK/corpus revision; state when it was not
  run (the checked-in harness is still incomplete, #114).
- Change generated kinds/views through their inputs and follow
  [syntax_codegen's procedure and checks](../syntax_codegen/README.md).
  Grammar and ungrammar changes must agree; run both `ConformanceTest.*` and
  `RepositoryConformanceTest.*`, not only the former.

Use [Development](../../docs/development.md#choose-checks-for-a-change) for the
broader required checks and SDK prerequisites.
