"""The threshold a report is held to: ceilings on counted work, never on time (D79).

`thresholds.toml` names, per server and scenario, the most a count may be (`cold_queries = 1200`),
and the options the counts hold for: a count is the same in every run of the same requests on the
same files, on any machine, so CI can fail on it where a timing on a shared runner would flake. A
report made with other options, or without a scenario the file names, fails the check rather than
passing it unmeasured.
"""

import pathlib
import tomllib

THRESHOLDS = pathlib.Path(__file__).resolve().parents[1] / "thresholds.toml"


def load(path: pathlib.Path = THRESHOLDS) -> dict:
    with open(path, "rb") as file:
        return tomllib.load(file)


def check(report: dict, limits: dict) -> tuple[str, list[str]]:
    """A Markdown table of every count against its ceiling, and what is over it or missing."""
    failures = []
    expected = limits.get("options", {})
    actual = {**report.get("options", {}), "generated": report.get("workspace", {}).get("generated")}
    for key, value in expected.items():
        if actual.get(key) != value:
            failures.append(f"the counts hold for {key} = {value!r}, the report has {actual.get(key)!r}")
    rows = ["| server | scenario | metric | runs | ceiling | |", "|---|---|---|---|---|---|"]
    for server, scenarios in limits.items():
        if server == "options":
            continue
        entry = report.get("servers", {}).get(server)
        for scenario, metrics in scenarios.items():
            result = (entry or {}).get("scenarios", {}).get(scenario)
            if result is None or result.get("status") != "ok":
                status = "not run" if result is None else result.get("status")
                failures.append(f"{server}/{scenario}: {status}")
                continue
            for metric, ceiling in metrics.items():
                runs = [run.get(metric) for run in result["runs"]]
                if any(value is None for value in runs):
                    failures.append(f"{server}/{scenario}: no {metric}")
                    continue
                worst = max(runs)
                over = worst > ceiling
                if over:
                    failures.append(f"{server}/{scenario} {metric} = {worst:g} > {ceiling}")
                # the same in every run, or it is no count to hold a server to
                varies = " (varies between runs)" if len(set(runs)) > 1 else ""
                mark = "**over**" if over else "ok"
                rows.append(
                    f"| {server} | {scenario} | {metric} | {', '.join(f'{v:g}' for v in runs)}{varies} | {ceiling} | {mark} |"
                )
    return "\n".join(rows), failures
