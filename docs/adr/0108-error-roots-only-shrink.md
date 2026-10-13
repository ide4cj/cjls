# ADR-0108: This repository's roots of an error type are held to a checked-in count per file and kind that only shrinks

Status: proposed
Amends ADR-0090: the gate also holds what no diagnostic shows

## Context

D90's gate holds this repository to zero diagnostics, but a diagnostic is only a mismatch or a count of arguments between types known wholly (A32): a name or member not found, a call not solved, a local of an error type show nothing. Those are counted by `InferenceCensusTest`, run by hand (`CJLS_CENSUS=1`), its numbers copied into #48's comments: a change that loses types elsewhere is found when someone next runs it. #48's plan (#340) wants each step of the inference to show its gain in its own diff, and the epic done when the false errors are gone.

On master `f03018b`, Linux: 224 roots of an `ErrorTy` in 69 (file, kind) pairs — 120 a local, 46 a member found, 27 a name not found, 12 a name found, 8 a call not solved, 6 an index, 5 an operator, 1 other.

## Decision

- **`ErrorRootsGateTest` holds them to `modules/project_model/error_roots_known.txt`**, a line `path: kind: count` per file and root kind (`rootKindOf`): a count grown fails, naming where each root of it is; one shrunk fails until `UPDATE_EXPECT=1` rewrites the file, as `std_diagnostics_known.txt` (D90). #48 is done with it empty.
- **Only `ErrorTy` roots.** cjc accepts these sources, so each is a false error of the analysis, and new code adds none unless it meets a gap. A `TodoTy` is a gap named (D77) and its count moves with any code (a new `remove(at:)` is one more `ArgMatching` until #254): held, it would make every unrelated change rewrite the file. Cascades follow their roots.
- **Per file and kind, not per kind alone nor per expression**: one gap closed and another opened in a kind of its own fail; a root's line or offset would move with every edit above it.
- **Linux alone** (`@When[os == "Linux"]`): the target picks which files of a source set are read (D99), so the counts are a target's; CI's Linux job holds them. The zero-diagnostic case stays on every platform.
- **The pass of `DiagnosticsGateTest`'s**: the workspace is the benches' one (`workspace()`), so the census reads what the gate inferred, about a second more.

## Consequences

- A step of #48 rewrites the file in its pull request, its diff the gain; one that loses types somewhere fails on its own commit, with the places.
- A false error met in new code is added to the file in the same pull request, and is seen there by its reviewer.
- A root kind's meaning changes with `rootKindOf`; a change to it rewrites the file.
