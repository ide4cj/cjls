# ADR-0127: Completion outside a body reads the position by the marker's parent: a type's path, an import, a line no declaration took, a member's name

Status: proposed

## Context

- D111 completes a `NameRef` under a `MemberAccessExpr` or a `RefExpr` alone; [#401](https://github.com/ide4cj/cjls/issues/401): a type (`let x: Fo|`, a parameter's, a supertype), a type's body between its members, the top level and an import completed nothing.
- In the speculative tree (D110) the marker is a `NameRef` of a `PathSegment` in a type, of an `ImportTree` in an import; where no declaration starts (a type's body, the top level), the parser's recovery puts the line in an `ErrorNode` (`skipToLineEnd`) whose first token is the marker; after `func` or `prop` in a type's body, it is the declaration's `Name`.
- R1 completes each by the position its `CompletionContext` classifies (`PathKind::Type`, `ItemListKind`, `ImportKind`) and, at an item list, offers the trait's missing items with their signature (`add_missing_impl_members` as completions). R4 completes a type position from the file's scope too, and keywords by a fixed list.

## Decision

- **The position is the marker's parent**, as D111's: a `PathSegment` of a `PathType` is a type, an `ImportTree` an import, an `ErrorNode` that starts with the marker a line between members (in a `DeclBody` or `EnumBody`) or at the top level (in the `SourceFile`), a `Name` of a `FuncDecl` or a `PropDecl` in a `DeclBody` a member's name. Anything else completes nothing still.
- **A type** lists what a type's path may start with (N51, N52): the type parameters of the item at the cursor and of the type around it, the types of the file's scope, read as D111 reads it with the values and the constructors left out, the packages it imports, and the primitive types as keywords. After one segment, which is an imported package, the types it exports.
- **An import** lists, of the packages `packageIndex` has for the file's module (itself, its deps, `std`, D46), the next segment of those whose names start with what the import writes before the cursor, the trees around a `{...}` included; after a package's full name and a `.`, what it exports. The file's own package is not among them.
- **A line no declaration took** lists keywords: between members, those starting a member and its modifiers; at the top level, those starting a declaration, with `import` while only the header and imports are before it and `package` before them too.
- **A member's name** lists the members of the type's supertypes of that kind (functions after `func`, properties after `prop`), static after `static`, that a subtype may override: an interface's, an `open` or `abstract` one, any of an `abstract` class (whose members without a body are open: the item tree does not tell a body), any static one; not a `private` one, nor one whose name the type declares already. The name alone is inserted: the signature as an edit is #401's open question.

## Consequences

- D111's "a cursor outside a body completes nothing yet" holds no more but for annotations (`@`), where the macros in scope need the macro host's list (D104).
- An `abstract` class's member with a body that is not `open` is offered after `override` though cjc rejects it; the item tree would need to say whether a member has a body.
- The type parameters of a local function around a type annotation in a body are not listed: the type scope is the item's (`typeScopeOf`), not the body's.
