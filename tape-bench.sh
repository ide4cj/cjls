#!/bin/bash
# Runs one bench class (argument 1) on a quiet machine: the 1-minute load below 2.5 before and
# below 4 after, else the run is dropped and tried again, six times at most. Log: argument 2.
export LD_LIBRARY_PATH=/home/filaco/.cjpm/toolchains/nightly-2026-10-02/runtime/lib/linux_x86_64_cjnative:/home/filaco/.cjpm/toolchains/nightly-2026-10-02/tools/lib
export cjHeapSize=4GB
here=/home/filaco/Projects/cjls/.claude/worktrees/agent-a3ae59ac64f7ca97f
class=$1
log=$2
load() { awk '{print $1}' /proc/loadavg; }
quiet_before() { awk '{exit !($1 < 2.5)}' /proc/loadavg; }
quiet_after() { awk '{exit !($1 < 4.0)}' /proc/loadavg; }
table() { grep -A14 "TCS: .*$class" "$1" | grep -E '^\s*\|' | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/.\[[0-9]*C//g'; }
for attempt in 1 2 3 4 5 6; do
  until quiet_before; do sleep 15; done
  l0=$(load)
  (cd "$here" && cjpm bench --target-dir target/bench "--filter=$class.*" > "$log" 2>&1)
  l1=$(load)
  quiet_after || { echo "attempt $attempt: disturbed, load $l0 -> $l1"; continue; }
  echo "attempt $attempt accepted: load $l0 -> $l1"
  table "$log"
  exit 0
done
echo "no quiet run in 6 attempts"
exit 1
