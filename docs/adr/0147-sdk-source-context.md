# ADR-0147: Binary sources resolve in a detached context with canonical binary declarations

Status: proposed
Amends ADR-0065: source attachments also provide a context for navigation within their files

## Context

D65 loads SDK sources as destinations without package membership. A project can
navigate to std, but no name resolves in the opened file (#492). D88 intentionally
discovers projects only under workspace roots, excluding the SDK. Loading std as
ordinary source modules would compete with installed `.cjo` declarations, including
compiler-provided types that have no source declaration.

## Decision

- Give attached source packages detached `Package` inputs, linked to their loaded
  `BinaryPackageFile`. Keep them outside `Project.modules` and the import index's
  candidates. Their imports use the owning binary's dependency lookup; other
  packages continue to import the binary. No extra workspace root or discovery is
  needed, including when the editor opens the file read-only.
- Resolve package declarations, members, extensions and language items through the
  binary. Read file imports and function bodies from source. Same-package lookup
  uses the binary file identity for private visibility. This retains the binary's
  overloads, platform selection and compiler-provided `std.core` declarations.
- Pair a source item with a binary item only at the binary's checked identifier
  position, using D65's name check. Parse only the requested file, retaining item
  identities rather than syntax trees. A source body keeps its source `DefId` for
  locals and ranges; self types and generic owners use its paired binary `DefId`.
  The file has a context only if at least one declaration pairs successfully.
- Within that detached context, supplement names missing from the binary with
  source declarations from files with checked pairs. Binary names and overload
  sets win. The binary omits implementation helpers such as `readFromConsole`;
  making only binary names available would still break browsing function bodies.
  Members absent from a binary type may likewise be read from its paired source
  type, only for a viewer in the same attached package.
- Do not reconstruct a second source type universe or match by names/signatures.
  The former could disagree with binary signatures and omit compiler types; the
  latter could pair an overload or platform branch from a different SDK.

## Consequences

Project → std → std navigation shares canonical types with project analysis, while
parameters and locals navigate within source bodies. Binary targets retain D65's
position/name validation. Missing binaries, absent sources and files with no
matching declarations acquire no source context. This is a declaration-level
check, not a cryptographic proof of the source version, as with D65.

Source packages do not add workspace symbols. Opening a source invalidates only
queries reading its text; replacing the project or attachment updates its inputs.
No readonly editor protocol is introduced (#272). Source-only implementation
helpers remain outside binary exports and project analysis. A declaration in a
file with no checked pair, or an unmatched overload of an existing binary name,
is not added by this mechanism.
