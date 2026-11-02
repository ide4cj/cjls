# ADR-0160: Audit written call bodies with explicit coverage gaps

Status: accepted, 2026-11-02

## Context

An audit of tracked queries needs possible call chains to declarations owned by
specific packages. Inference retains selected callees but is not a complete call
graph. Navigation drops unavailable binary locations; ordinary Call Hierarchy
also attributes anonymous lambdas to their enclosing function. Those choices
cannot justify negative reachability answers. Calca wrappers add implementation
calls that do not belong to the original tracked function's user body.

## Decision

Provide an explicitly requested immediate-call query in loupe, keyed by DefId,
with declaration identity, source site, resolution character and coverage gaps.
Share call-site declaration resolution with Call Hierarchy before conversion to
navigation entries. Keep original tracked source bodies as audit roots and map
copied CalcaTracked declaration names back to that source identity. Do not
interpret Calca's generated wrapper as additional user-body execution.

Prune nested function/lambda bodies unless their execution is modeled. Report
unsupported value flow, dispatch, initialization, macro behavior and unavailable
bodies explicitly. Do not invent library callback models. Other macros remain
coverage gaps. Their token arguments are not unconditional calls.

Run transitive searches in the requesting client, over this common model.
Breadth-first search finds a minimum number of edges per reachable declaration;
retain conservative edge labels and propagate successor gaps independently of
positive findings. No deep analysis becomes an inference or LSP prerequisite.

## Consequences

The first stage is useful evidence but cannot certify the full requested audit.
Functional value flow and runtime/implicit targets can extend the same edge and
gap contract in later PRs. The loupe call model documents its coverage contract
independently of clients. An empty incomplete traversal remains unknown. A negative answer is scoped to the constructed model.
