# ADR-0155: Independent dependency selections retain module and source context

Status: proposed

## Context

cjpm resolves ordinary/test dependencies and build-script dependencies independently.
The same module name may select different commits in `requires` and `scripts`;
even one local path may import different transitive selections (#515).
The old loader memoized paths and indexed imports by module name, conflating both
graphs. Giving packages separate owners alone still shares `SourceFile` and
`DefId`: signature and body queries recover their package from the file.

## Decision

Carry an optional resolution scope through the project model and JSON projection.
Include it in module/package identity and qualify source import owners by it;
package names and visibility rules keep their language meaning. The default scope
retains existing project-file behavior. cjpm build scripts use an entry-specific
scope, while ordinary modules use the default scope.

Precreate contextual source inputs for scoped packages during project input writes.
They share physical `FileId` and text with the ordinary input, but have distinct
analysis identity and an explicit package context. `AnalysisDatabase.setFileText` updates all contextual inputs. Macro outputs remain per analysis context: expansions can
differ with the dependency selection. Macro rounds enumerate every active source
context, and macro compiler cache directories include the resolution scope so
same-named macro packages from different graphs cannot overwrite each other.
The SDK macro server can retain a same-named library or reuse transitive native
dependencies across different macro packages (K28). Workspace requests restart
that process whenever the active library path switches; std retains its
independent process. Repeated calls into one library reuse its process; switching
libraries pays process startup even when their dependencies happen to agree. Queries only read
existing inputs.

A single global name map cannot represent two selected commits. Renaming source
packages would change language names and visibility. Copying files into synthetic
VFS paths would lose physical navigation and editor updates. Explicit source
contexts preserve both physical locations and contextual declaration identity,
following the distinction between attachment context and physical source in D147.

## Consequences

Repeated discovery and project merging retain separate same-path contexts.
Text edits invalidate each context, while a context's dependency/configuration or
macro-output changes affect that context's analysis. More input identities are
retained, bounded by the package contexts discovered over the session.

The ordinary `sourceFile(FileId)` lookup prefers an ordinary membership, otherwise
the first active scoped membership, through a tracked project input. cjpm's
projection also puts ordinary modules before build-script contexts. This makes editor queries agree with the selected
package's exported declaration identities, including script-only dependencies.
Package-driven analysis uses explicit contextual lookups; references scan each
source context and deduplicate their physical result locations. This does not add an editor control for choosing an arbitrary dependency
graph for a file opened from two graphs.
