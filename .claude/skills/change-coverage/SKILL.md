---
name: change-coverage
description: How well the tests cover the files a branch changed — the coverage build (D49), then each changed source file's hit/total against master's. Use before opening a PR that adds or rewrites code in modules/*/src, or when asked what a change leaves untested.
---

1. Build and run the tests instrumented, in a target dir of their own (CLAUDE.md, *Build & test*):
   `cjpm test --coverage -g --no-progress --timeout-each=2m --target-dir target/cov`, then
   `cjcov -r . -s modules -x -j --html-details -o coverage`.
2. The changed files' coverage (what `.github/scripts/coverage.py` counts: `modules/*/src/**` minus tests, generated, macro and test-support files):

   ```sh
   python3 - $(git diff --name-only --diff-filter=AM "$(git merge-base origin/master HEAD)" -- 'modules/*/src/*.cj') <<'EOF'
   import json, sys
   files = {f["filepath"].replace("\\", "/"): f for f in json.load(open("coverage/coverage.json"))["fileLists"]}
   for p in sys.argv[1:]:
       if p.endswith("_test.cj"):
           continue
       f = files.get(p)
       print(f"{p}: {len(f['hitLines'])}/{f['totalLines']}" if f else f"{p}: not in the report")
   EOF
   ```
3. Lines not hit: `coverage/index.html` and the per-file pages beside it. Read them for the lines the diff added.
4. Report per file `hit/total`, and the added lines no test runs, grouped by what they do (an error path, a branch of a match). A line only an e2e test could reach says so (C7); everything else is a missing unit or fixture case to write.

`coverage/` is untracked output; leave it.
