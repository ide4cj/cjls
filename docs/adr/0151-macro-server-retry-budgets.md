# ADR-0151: Repeated macro server failures have scoped retry budgets

Status: proposed
Amends ADR-0087: repeated failures no longer restart the server for every call

## Context

An SDK macro server that cannot load a library exits on every call. Restarting
for every pending expansion repeats SDK stderr and cjls warnings, potentially
hundreds of times (#506). Deduplicating warnings alone leaves process churn and
SDK output unchanged. The protocol reports disconnects without distinguishing
loader errors from a macro crash, so permanently disabling a library on its first
disconnect would prevent recovery and can hide healthy macros.

## Decision

Allow three failures before a 60-second cooldown. After cooldown, one incoming
call probes again; a failed probe starts another cooldown. No timer schedules
retries and existing failed analysis outputs are not invalidated by time alone.

Before a library has returned a protocol answer, share disconnect failures across
its methods. After an answer, including a failed expansion, use method budgets:
the library has demonstrated that it can load. Timeouts always use method
budgets, so a looping macro does not pause other methods. Process-start failures
have one budget per guarded server. Other libraries and the separate std and
workspace servers remain eligible.

A protocol answer resets its method and library budget. Workspace rebuilds
explicitly restart their server and clear history. Changes in library size or
nanosecond modification time also clear history and unload the running process.
Changing the selected SDK or timeout creates new guarded servers. Metadata is
not a content digest: a same-path repair preserving size and modification time
uses the cooldown or an explicit reload to recover.

Keep SDK stderr inherited for actual attempts. Suppressed calls neither start a
process nor send an expansion and therefore produce no SDK output. Log the first
failure with library, macro and exception; log entering cooldown with retry
instructions. Further failures inside the initial allowance need no cjls warning.
Tests replace the clock and session to count starts, attempts and warnings, and
fire deadlines explicitly.

## Consequences

An initially unloadable library costs at most three attempts, then at most one
failed probe per minute of incoming calls. A single crash or timeout retains
immediate retry. A library that never answered can temporarily pause healthy
methods too; the bounded cooldown and rebuild/reload reset provide recovery
without pretending to classify the SDK's failure. Once a library has answered,
repeated crashes in one method do not pause its siblings. A successfully loaded
library whose external dependencies later break is limited per method until its
own metadata changes or the server is reloaded.
