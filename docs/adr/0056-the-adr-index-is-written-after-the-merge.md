# ADR-0056: The ADR index is written after the merge by a bot; a number is taken when the ADR is started, and checked to be the only one

Status: accepted, 2026-10-07

## Context

- Every ADR PR added a row at the end of `docs/adr/README.md`'s table, so any two in flight conflicted there (#147); PRs come in bursts (D38–D41 in two days, D44–D55 in three).
- A table written by a script and committed by each PR conflicts all the same: both PRs insert at the end. `merge=union` in `.gitattributes` is git's alone; GitHub's merge ignores it.
- Two PRs taking one number do not conflict at all: `0056-a.md` and `0056-b.md` are two paths, and the second merges silently. The ruleset does not require a branch up to date with master.
- A decision is cited as `D#` in its own PR, in CLAUDE.md and in `design/` as it is written: the number must exist before the merge.
- The index said more than the files: the decisions were longer than the ADRs' titles, and what a later ADR changed in an earlier one (`stamps by D28`) was in the index alone.
- The organization's app pushes to master past the ruleset already (`bump.yml`, D21, D32).
- The rules of `design/` (`A#`, `C#`, …) are counters too.

## Decision

- **The table is written by `scripts/docs.py index`, run by `docs.yml` on a push to master** that changes an ADR, and pushed as `index(adr): …` by the app: a PR does not touch it, so no two PRs meet in it. Rejected: the number given at the merge (a `D#` not citable in its own PR), dropping the table (what amends what is seen nowhere), dates or slugs for numbers (every citation rewritten).
- **The table is the headers': the title is the decision, the `Status` line the status, and an `Amends ADR-NNNN: <what>` line of a later ADR is shown in the earlier one's row** (`<what> by D#`). The earlier file is not touched. The titles took the index's longer wording, and the amending ADRs their `Amends` lines, once.
- **A number is taken by `scripts/docs.py new-adr`**: the next after this branch's, `origin/master`'s and the open PRs' (`gh`).
- **`scripts/docs.py check` is a job of `ci.yml`** (`Docs ids`): every ADR number and rule id once, every ADR header readable, the `Amends` and `superseded by` naming an ADR there; on a PR, no older open PR adding an ADR of the same number (the younger renumbers). `docs.yml` runs it on master before the index.
- **`index` is a commit type of its own**, `omit_from_changelog` in `cog.toml`: the PR that changed the ADR is in the changelog.

## Consequences

- A PR's ADR has no row until its merge; the bot's commit follows each merge that changes an ADR, and starts `ci.yml` on master.
- Two PRs that took a number before either pushed its ADR can both pass: `docs.yml` goes red on master, and the later one is renumbered by hand.
- A row is written only as the header is: a decision reworded in its title is reworded in the index.
