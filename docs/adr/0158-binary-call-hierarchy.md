# ADR-0158: Call hierarchy keeps binary identity without requiring source navigation

Status: proposed

## Context

Call hierarchy was built from navigation targets. A binary declaration without
attached sources has no navigation target, although inference knows exactly
which overload the call uses. Even with sources, compiler declaration ranges
can omit annotations included by the syntax node, so exact range equality
discarded valid functions such as `println`.

## Decision

Resolve callable declarations before locating them. Keep the canonical binary
`DefId` on a hierarchy entry, including entries reached through attached source
declarations. Group and match binary call edges by this identity, so different
references and overloads remain distinct independently of their locations.

With checked attached sources, use the callable syntax node at the identifier,
without requiring the compiler's full range to equal the syntax range. D65's
position/name check still gates binary source navigation.

Without sources, use the referring name as the entry's location. This gives
editors a real source location to reveal and to re-resolve on subsequent requests.
It does not claim to locate the binary declaration. Returning no node loses
known incoming edges; pointing at `.cjo` bytes invents text positions, and a
synthetic source document would require a separate client content protocol.
Server handlers continue re-resolving locations against the current snapshot.
Binary item data carries the binary name, `.cjo` path, source-file index and
structural item ID, compared against the freshly resolved candidates. This
distinguishes overloads sharing one reference location and rejects a reference
that now resolves to another overload. Interned handles never travel in LSP data.

## Consequences

Binary functions participate in prepare, incoming calls and callers' outgoing
calls without source attachments. Repeated references group by declaration,
not by the fallback location, and overloads remain separate. A binary function
without a readable source body has no outgoing edges; no body is inferred from
its referring site's enclosing function. Attached source bodies remain browsable.

The fallback location depends on the reference used to reach the function. If
that reference is removed, a later request using the old item can no longer
resolve it. This is the existing location-based refresh contract, not a persistent
symbol handle.
