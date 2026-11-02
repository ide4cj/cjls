# ADR-0160: Audit written call bodies with explicit coverage gaps

Status: accepted, 2026-11-02

## Context

Tracked queries can return stale cached results if they read files, clocks or
randomness outside declared inputs. Auditing those paths needs declaration
ownership and call evidence. Inferred callees alone omit unsupported execution,
and Call Hierarchy attributes anonymous lambda calls to their enclosing function.
Neither can establish absence of a path. Calca wrappers also add infrastructure
calls outside the original tracked body.

## Decision

Expose immediate call evidence in loupe, sharing declaration resolution with
Call Hierarchy while retaining coverage gaps. Audit original CalcaTracked bodies
and map copied expansion declarations back to their source identity. The current
constraints are [A39](../design/02-analysis.md#a39-partial-call-evidence).

Keep transitive traversal in the requesting client: its target selection and
search policy do not belong in language inference or an LSP prerequisite.
A dedicated call model can improve independently of interactive analysis.

## Consequences

Clients can find possible call chains and distinguish missing evidence from
modeled absence. This partial model cannot complete the tracked-query audit;
functional value flow, runtime dispatch and implicit effects need further work.
API details and omission reasons stay beside the source in
[`direct_calls.cj`](../../modules/loupe/src/direct_calls.cj).
