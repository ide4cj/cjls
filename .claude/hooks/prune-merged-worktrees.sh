#!/usr/bin/env bash
# Compatibility entry point: automatic deletion was unsafe for active sessions.
# See docs/procedures.md; this script deliberately has no filesystem/network effects.
printf '%s\n' 'Automatic worktree cleanup is disabled. Follow docs/procedures.md#worktree-lifecycle.' >&2
