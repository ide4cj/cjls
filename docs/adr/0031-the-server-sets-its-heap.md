# ADR-0031: The server starts over with a heap of 2 GB, and a load keeps a sixteenth of the heap

Status: accepted, 2026-09-29

## Context

- The runtime's heap is 256 MiB unless `cjHeapSize` says otherwise, read from the environment once, before `main`; editors start the server without it (D30).
- Servers on a runtime with a heap limit have the client pass it, from a setting with a large default: tsserver's `maxTsServerMemory` (3 GB, `--max-old-space-size`), jdtls's and Metals' `-Xmx`. Those runtimes' own defaults are already a share of the machine's memory; the Cangjie runtime's is fixed.
- Every client would have to know the variable: the Neovim, VS Code and Zed integrations (D16), and every editor configured by hand.
- A limit takes no memory until used: idle, the server is 11.8 MB of RSS under 256 MiB, 2 GB or 8 GB. The runtime takes `KB`, `MB`, `GB` in any case, from 4 MB to the machine's memory; outside that, it writes an error to stderr and keeps its default.
- D30's budget of 16 MiB was measured on the default heap: 32 MiB of text ran out of memory on the first search.

## Decision

- **Without `cjHeapSize`, the server sets it to `2GB` and starts over** before it reads anything: `execvp` of its own command line on POSIX, the same process and stdio; on Windows a child on the same stdio, whose exit code is the server's. A value the user set is kept. If starting over fails, a `WARN` and the default heap.
- **A load keeps at most a sixteenth of the heap** (`getMaxHeapSize()`), D30's ratio: 128 MiB on 2 GB, 16 MiB on the default heap still, whatever value the runtime refused.
- The heap is logged at `INFO` on start.

## Consequences

- On the release binary (macOS arm64): `cangjie_test`'s `LLT` loads whole, 32 748 files in 4.2 s with a search over all of them, 813 MB peak RSS; all of `cangjie_test` keeps 41 952 files (763 before) in 7.1 s, a full search takes 9 s, 971 MB peak.
- A client need not know the variable; one can still set it, as a setting of its own.
- On Windows two processes run, the parent only waiting.
- The budget still bounds a root far wider than a project; a project model from `cjpm.toml` (#69) is what stops loading what is not one.
