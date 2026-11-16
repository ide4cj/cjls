# Load a library and check its adapter boundary

Resolve/build the project's declared dependencies with its normal cjpm command
before querying. For a path dependency, keep its own manifest, package name and
source root; for Git dependencies keep the resolved lockfile. Use the consuming
project's root on every runPython call. Do not load a library's src directory as
an unrelated script and infer that its dependencies are available.

This scenario expects a consumer at src/main.cj, an adapter at src/adapter.cj,
and a path dependency at deps/library with public parseToml. Adapt the explicit
paths and names to the migration. It checks loaded permissions separately from
actual references, retains ambiguous evidence, and reports all counts before
paging. Binary-only declarations need semantic exports instead of fileSymbols;
report that gap rather than claiming zero callers.

~~~python
from pathlib import Path
a = workspace.analysis()
s = a.semantic()
root = Path(workspace.root)
consumer_sources = root / "src"
adapter_path = str(root / "src/adapter.cj")
library_path = str(root / "deps/library/src/lib.cj")
project = s.project()
dependencies = [{"name": d.name, "resolved": d.isResolved,
                 "test_only": d.isTestOnly,
                 "modules": [m.name() for m in d.modules]}
                for d in project.dependencies()]

def inspect_target(path, name, allowed_path=None):
    selected = exact_symbols(a, [path], name)
    assert len(selected) == 1, "select the intended overload before checking the boundary"
    symbol = selected[0][1]
    declaration = s.at(a.fileId(path), symbol.selectionRange.start)
    assert declaration is not None and len(declaration.definitions) == 1
    target = declaration.definitions[0]
    rows, violations, uncertain = [], [], []
    for ref in a.references(path, symbol.selectionRange.start):
        if ref.isDeclaration:
            continue
        ref_path = a.path(ref.fileId)
        try:
            Path(ref_path).relative_to(consumer_sources)
        except ValueError:
            continue  # Check this consumer's boundary, not other dependents.
        occurrence = s.at(ref.fileId, ref.range.start)
        resolution = None if occurrence is None else occurrence.resolution()
        status = None if resolution is None else resolution.status.kind
        definitions = [] if occurrence is None else (occurrence.definitions or [])
        exact = (status == "ResolvedMeaning" and len(definitions) == 1
                 and definitions[0].identity == target.identity)
        row = {"path": ref_path, "range": ref.range, "status": status,
               "exact_target": exact}
        rows.append(row)
        if not exact:
            uncertain.append(row)
        if allowed_path is not None and ref_path != allowed_path:
            violations.append(row)  # Includes possible bypasses, not only proven calls.
    return {"references": result_page(rows), "violations": result_page(violations),
            "uncertain": result_page(uncertain), "gaps": target.usages().gaps}

library = inspect_target(library_path, "parseToml", adapter_path)
adapter = inspect_target(adapter_path, "decode")
result = {"root": workspace.root, "load_diagnostics": workspace.loadDiagnostics,
          "macros": workspace.macros, "dependencies": result_page(dependencies),
          "library": library, "adapter": adapter}
~~~

Check that the intended dependency is resolved, the library has observed exact
uses in the adapter, and the adapter has observed exact consumer uses. Review
all violation/uncertain pages and coverage gaps; zero rows alone proves nothing.
A dependency permission is not an import or call. This checks written reference
boundaries, not runtime reachability or generated macro bodies.

After migration, run this query in a fresh call and compile/test the consumer
with the old implementation removed. Exercise adapter behavior (success, parse
errors, encoding/round-trip where relevant) and the normal build route. An empty
diagnostic list has missed undeclared types in real migrations; it cannot replace
compiler validation. Do not edit resolved cache dependencies to hide failures.
