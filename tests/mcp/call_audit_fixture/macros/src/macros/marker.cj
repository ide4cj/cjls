macro package calca.macros

import std.ast.*

// These identity overloads exercise audit selection without linking Calca's runtime.
public macro CalcaTracked(input: Tokens): Tokens { input }
public macro CalcaTracked(attrs: Tokens, input: Tokens): Tokens { input }
