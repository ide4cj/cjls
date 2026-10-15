# ADR-0121: A known gap met by new code grows the error roots file; the code stays idiomatic and the commit names the gap

Status: proposed
Amends ADR-0108: the file only shrinks

## Context

- D108 holds this repository's roots of an error type to `error_roots_known.txt`, a count per file and kind, and says the file only shrinks: a count grown fails the gate with where each root is. Its consequences already allow "a false error met in new code" to be added in the same pull request, but the rule as stated, and the file's header, say the opposite, and the gate's failure reads as a defect of the change.
- What that leads to, seen on #380: `… |> fold(0) {a, b => a + b}` met #246 (a generic call as a callee is solved without the pipeline's left, N131), the gate failed, and the sum was rewritten as a `for` loop over a `var` to keep the count. The code of this repository then bends around the analysis's gaps: less idiomatic, and a gap met one time less, which is the opposite of what the census is for (#48 wants the gaps closed, not avoided).
- The file is written by the gate under `UPDATE_EXPECT=1`, header kept, lines regenerated: nothing written beside a count survives a rewrite, so the reason of a growth cannot live in the file.

## Decision

- **Code is written as it would be without the gate.** A construct the analysis types wrongly is not rewritten to keep a count; the gate reports the gap met, not a defect.
- **A count grown by new code meeting a known gap is written into the file** the same way a shrunk one is (`UPDATE_EXPECT=1` on Linux), in the same pull request.
- **The gap is named at the root**: a comment on the line that the gate reports, giving the gap's issue (`// \`b\` is a root of an error type until #246`, D121), and the commit message says which lines grew and by which issue. A root no issue covers is a new gap: its issue is opened first, and the comment names it.
- A rewrite that loses types elsewhere still fails on its own commit, as D108 says: only a growth whose roots are commented and attributed passes review.

## Consequences

- The file now moves in both directions; the diff of a pull request shows each growth with its comment, and the census's numbers in #48 count the gaps met as well as the gaps left.
- Closing a gap takes off its comments too: a search for the issue's number finds them.
- Code that bent around a gap before this decision stays as it is until touched.
