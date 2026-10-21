# ADR-0106: The server's own directory is <project>/.cache/cjls, owned by one type, with a layout and a lifecycle

Status: accepted, 2026-10-20

## Context

- The macro build (#326, D104) and the expanded files (#327, D103) each wrote a `.cjls/` of their own (#333). The two chose its root differently: the first workspace folder, or the innermost root, else the file's own directory, so a loose file got a `.cjls` beside it. Each wrote its own `.gitignore`. Nothing was ever removed: a `macros/<cjc --version>/` per nightly used, every expanded file shown. Two servers on one project built into one directory at once. A tree the server cannot write ran no macro.
- clangd keeps its index in `.cache/clangd/` beside `compile_commands.json`, and stops writing there when it cannot. A project's `.cache/` is a name editors, ignore files and tools already know.
- cjpm's own output is `target/`, which a `cjpm clean` empties and a build of the user's may hold. D87 keeps the server out of it.

## Decision

- **Where:** `<project>/.cache/cjls/`. `<project>` is the directory of the project a file is of, a `cjpm.toml` workspace or a `cj-project.json` (`projectDirOf`), up to the innermost root it is under, else that root. Under no root, it is the project above the file, else the file's own directory. When `<project>/.cache/cjls` cannot be written, it is `<user cache>/cjls/<name>-<hash of the path>/` (`$XDG_CACHE_HOME` or `~/.cache`, `~/Library/Caches`, `%LOCALAPPDATA%`), which names its project in `BASE`. Which directory that is per OS is `platform`'s `userCacheDir` (D101).
- **One owner:** `cjls.server`'s `CacheDirs` and `CacheDir` (`server/cache_dir.cj`). Nothing else names a path in it.
- **Layout:**

  | path | what |
  |---|---|
  | `.gitignore` | `*` |
  | `CACHEDIR.TAG` | so that backup tools skip it |
  | `LAYOUT` | its number; a directory without it, or with another, is emptied first |
  | `macro-build/<compiler>/` | the macro packages built (D104); `.used` holds when it was last used, and `lock` is its lock |
  | `expanded/<path under project>.macrocall` | the expanded files shown (D103) |

- **Lifecycle:**
  - The directory is made, and set in order, when a server first opens it.
  - Opening it also empties `expanded/`, since the server remembers none of those files (D103).
  - It removes a `macro-build/<compiler>/` unused for a week, unless a build holds its lock.
- **The lock** is the OS's own on the open file `lock` (`platform`'s `tryLockFile`: `flock`, `LockFileEx`, D101), never waited for. The OS releases it when the process dies, so no lock is left behind by a crash.

## Consequences

- A project switched between nightlies keeps one build per compiler used within the week. Every older one goes when a server next opens the directory.
- A second editor on the project empties `expanded/` under the first one's open expansion. Its tab keeps its text, and the first server answers in it while that is what it would write (D103).
- A build that starts in a `macro-build/<compiler>/` between its lock file's removal and the directory's goes on with no lock. That takes a directory unused for a week, chosen at that very moment.
- `.cache/` itself is the user's. cjls writes only `.cache/cjls/`, and ignores it in version control from inside, so a repository that does not ignore `.cache/` stays clean.
