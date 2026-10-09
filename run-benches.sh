#!/bin/bash
# The three bench classes of the tape experiment, each on a quiet machine; argument 1 tags the logs.
here=/home/filaco/Projects/cjls/.claude/worktrees/agent-a3ae59ac64f7ca97f
tag=$1
for class in FjTapeBench FjTapeBBench FjTapeAllocationBench FjRpcBench; do
  echo "== $class"
  bash "$here/tape-bench.sh" "$class" "$here/bench-$tag-$class.log"
done
