# ADR-0163: The formatter normalizes import blocks

Status: accepted, 2026-11-03

## Context

Equivalent import layouts should have the same output in the CLI, LSP and
generators: `import p.{A}` is `import p.A`, and separate imports of `p.A` and
`p.B` can be written as `import p.{A, B}`. D150's literal token/tree preservation
prevents both normalization and C28's package/member ordering.

## Decision

Narrow D150's preservation contract for imports. Normalize consecutive
comment-free declarations: sort std, stdx and other packages in that order,
then packages and names alphabetically; combine explicit names from the same
package only when visibility and annotation tokens match. Whitespace outside
annotation literals does not distinguish conditions. Public reexports follow
the same rule. Preserve every imported path, alias, condition and visibility,
including duplicate names. Keep wildcard imports separate from explicit names;
never infer redundancy from `*` or remove unused imports.

Comments within or attached to declarations and inline trailing comments anchor
those declarations. Other comments, semicolons and non-import syntax end a run;
blank lines alone do not. Preserve trailing commas when regrouping explicit
names. Strings and macro token trees remain protected. Files with parser errors
are refused as before; parser-accepted empty import lists remain untouched.

Normalize source spans before layout, reparsing only when imports change. This
reuses width, indentation and comment printing without adding semantic queries
or configuration. Import-only ranges normalize the enclosing selected imports,
including trailing comment context; they do not reformat other imports or code.
Other ranges retain D150's enclosing statement/body policy.

## Consequences

Preservation checks independently compare the multiset of fully qualified
imports with their aliases and prefixes, comment content/order, and the tokens
and reparsed structure outside import declarations. Expected-output tests cover
AAA-marked parameterized cases, barriers, widths, conditions and range isolation.
The source migration and regenerated files use the same shared formatter.
