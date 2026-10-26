# ADR-0144: A body lowers current expression expansions in place, with file-qualified source maps

Status: accepted, 2026-10-23
Amends ADR-0117: a body's current expression and statement expansions are lowered and inferred (#369)
Amends ADR-0132: a body source map can contain nodes from several expansion files

## Context

D117 already finds and runs calls inside bodies, but their answers do not reach
lowering. `BodySourceMap` identifies nodes by kind and range in the body's file.
Two expression expansions can have identical ranges and kinds, so adding their
nodes to those indexes would confuse unrelated expressions and diagnostics.
Completion also lowers a speculative tree whose calls have no server answers.

## Decision

- Lower a current successful answer in the call's lexical scope. An expression
  replaces the call's value; a statement expansion is spliced into the surrounding
  statement list, without an extra block. Its declarations are visible afterwards.
- Qualify every expression, pattern, local and type source with `BodySource`: a
  syntax pointer and an optional expression expansion call. Without that call the
  pointer belongs to the body's own file, which may itself be an item expansion.
  Reverse indexes use the qualified source. A source call also aliases the
  expression lowered from its output, without adding another HIR expression.
- Keep the plain `lowerBody` independent of the database and expansion answers.
  `bodyWithSourceMap` supplies the current answers to the same lowering code;
  speculative completion therefore retains D59's reading of arguments.
- An absent, outdated, failed or unparseable answer uses that fallback. A failure
  must not read the successful output retained by D98 under the new fingerprint.
- Inference diagnostics use each expression's file, then its spans: copied text
  maps to source, generated text to the call head. Generated calls have no source
  key and are not recursively expanded, as D117 already specifies.

Rejected: unqualified pointers with offset adjustments, which confuse source and
output nodes; a separate synthetic block around statement expansions, which hides
their declarations; reading retained expression output after an edit, whose spans
and bindings may no longer describe the call.

## Consequences

One body can resolve generated locals and infer generated expressions together
with source expressions. Source maps and their consumers must preserve the file
qualification; hover and definition in an expression expansion use that same body.
Navigation from source arguments into their copies remains #370; nested request
composition remains #371, and std.unittest expression requests remain #375.
