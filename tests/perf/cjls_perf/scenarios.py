"""What is measured: each scenario starts a server of its own and returns its metrics.

A metric's name carries its unit (`_ms`, `_mb`, `_s`); a count has none. A scenario that needs a
capability the server does not advertise is skipped, not failed: the servers do not all do the
same things, and a missing feature is prior-art.md's business, not a number here.
"""

import asyncio
import statistics
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass

from pygls.exceptions import JsonRpcException

from . import places
from .session import Session, column

CONTENT_MODIFIED = -32801


class Skipped(Exception):
    pass


@dataclass
class Options:
    keystrokes: int = 50
    requests: int = 50


Scenario = Callable[[Session, Options], Awaitable[dict[str, float]]]
SCENARIOS: dict[str, Scenario] = {}


def scenario(name: str):
    def register(function: Scenario) -> Scenario:
        SCENARIOS[name] = function
        return function

    return register


def percentile(values: list[float], p: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, round(p / 100 * (len(ordered) - 1)))]


def count(symbols: list) -> int:
    return sum(1 + count(getattr(s, "children", None) or []) for s in symbols)


async def start(session: Session) -> dict[str, float]:
    await session.initialize()
    initialized = session.since_start_ms()
    return {"initialize_ms": initialized, "ready_ms": await session.ready()}


@scenario("startup")
async def startup(session: Session, options: Options) -> dict[str, float]:
    """From the process spawned to its `initialize` answer, then to ready; what it costs to sit there."""
    metrics = await start(session)
    usage = session.usage()
    return {**metrics, "rss_ready_mb": usage.rss_mb, "peak_rss_mb": usage.peak_rss_mb, "cpu_s": usage.cpu_s}


@scenario("open")
async def open_document(session: Session, options: Options) -> dict[str, float]:
    """The subject opened, until its first outline: the first read of a file, a cold one."""
    await start(session)
    if not session.supports("document_symbol_provider"):
        raise Skipped("no documentSymbolProvider")
    before = session.usage()
    session.sampler.reset_peak()

    text = session.workspace.subject_text
    began = time.perf_counter()
    uri = session.open(session.workspace.subject, text)
    symbols = await session.symbols(uri)
    elapsed = (time.perf_counter() - began) * 1000

    after = session.usage()
    return {
        "open_to_symbols_ms": elapsed,
        "symbols": count(symbols),
        "rss_mb": after.rss_mb,
        "rss_growth_mb": after.rss_mb - before.rss_mb,
        "peak_rss_mb": after.peak_rss_mb,
        "cpu_s": after.cpu_s - before.cpu_s,
    }


@scenario("typing")
async def typing(session: Session, options: Options) -> dict[str, float]:
    """A declaration typed at the end of the subject, a character at a time, the outline asked for
    after each: the latency an editor refreshing its outline sees, and the memory edits leave."""
    await start(session)
    if not session.supports("document_symbol_provider"):
        raise Skipped("no documentSymbolProvider")
    text = session.workspace.subject_text
    uri = session.open(session.workspace.subject, text)
    await session.symbols(uri)
    before = session.usage()
    session.sampler.reset_peak()

    # the end of the file, in the columns agreed on; what is typed is ASCII, so it moves by one
    lines = text.split("\n")
    line, character = len(lines) - 1, column(lines[-1], session.encoding)
    typed = "\nfunc typed(x: Int64): Int64 {\n    x + 1\n}\n"
    latencies = []
    version = 1
    for i in range(options.keystrokes):
        char = typed[i % len(typed)]
        version += 1
        began = time.perf_counter()
        session.insert(uri, version, line, character, char)
        await session.symbols(uri)
        latencies.append((time.perf_counter() - began) * 1000)
        line, character = (line + 1, 0) if char == "\n" else (line, character + 1)

    after = session.usage()
    return {
        "keystroke_p50_ms": statistics.median(latencies),
        "keystroke_p95_ms": percentile(latencies, 95),
        "keystroke_max_ms": max(latencies),
        "rss_mb": after.rss_mb,
        "rss_growth_mb": after.rss_mb - before.rss_mb,
        "peak_rss_mb": after.peak_rss_mb,
        "cpu_s": after.cpu_s - before.cpu_s,
    }


def answered(answer) -> bool:
    return bool(getattr(answer, "items", answer))


# what the edit of the navigation scenarios adds at the end of the subject: a declaration, so the
# file's declarations change, not only its text
EDIT = "\nfunc perfEdited(x: Int64): Int64 { x }\n"


async def navigate(session: Session, options: Options, capability: str, ask, where) -> dict[str, float]:
    """The subject opened, then a request at each of `options.requests` places, in three passes:
    straight after the open (`cold`; the first request, `first_ms`, reads the file and what it
    needs), again (`warm`: answered from what the first pass left), and again after a declaration
    is added at the end of the file (`edit`: what an edit elsewhere costs the same answers).

    With `cjls/analysisStats` each pass also counts the queries it executed: the work, the same in
    every run, which `thresholds.toml` holds the server to (D81). Nothing else runs meanwhile: the
    driver pulls diagnostics, so none are computed behind the requests' back."""
    await start(session)
    if not session.supports(capability):
        raise Skipped(f"no {capability}")
    text = session.workspace.subject_text
    asked = places.spread(where(text, session.encoding), options.requests)
    if not asked:
        raise Skipped("nowhere to ask in the subject")
    uri = session.open(session.workspace.subject, text)

    async def one_pass() -> tuple[list[float], int, int | None]:
        before = await session.queries_executed()
        latencies, found = [], 0
        for line, character in asked:
            began = time.perf_counter()
            answer = await ask(session, uri, line, character)
            latencies.append((time.perf_counter() - began) * 1000)
            found += answered(answer)
        after = await session.queries_executed()
        return latencies, found, None if before is None else after - before

    cold, found, cold_queries = await one_pass()
    warm, _, warm_queries = await one_pass()
    lines = text.split("\n")
    session.insert(uri, 2, len(lines) - 1, column(lines[-1], session.encoding), EDIT)
    edited, _, edit_queries = await one_pass()

    metrics = {
        "first_ms": cold[0],
        "cold_p50_ms": statistics.median(cold),
        "cold_p95_ms": percentile(cold, 95),
        "warm_p50_ms": statistics.median(warm),
        "edit_first_ms": edited[0],
        "edit_p50_ms": statistics.median(edited),
        "requests": len(asked),
        "found": found,
    }
    if cold_queries is not None:
        metrics |= {"cold_queries": cold_queries, "warm_queries": warm_queries, "edit_queries": edit_queries}
    return metrics


@scenario("definition")
async def definition(session: Session, options: Options) -> dict[str, float]:
    """Go to definition on names spread over the subject: cold, warm, and after an edit."""
    return await navigate(session, options, "definition_provider", Session.definition, places.uses)


@scenario("hover")
async def hover(session: Session, options: Options) -> dict[str, float]:
    """Hover on names spread over the subject: cold, warm, and after an edit."""
    return await navigate(session, options, "hover_provider", Session.hover, places.uses)


@scenario("completion")
async def completion(session: Session, options: Options) -> dict[str, float]:
    """Completion right after the `.` of member accesses spread over the subject: cold, warm, and
    after an edit. Skipped by a server without `completionProvider` (cjls until #203)."""
    return await navigate(session, options, "completion_provider", Session.completion, places.members)


@scenario("typing_hover")
async def typing_hover(session: Session, options: Options) -> dict[str, float]:
    """The cancellation path: a declaration typed at the end of the subject two characters at a
    time, a hover asked after each on a name in the middle of the file. The first hover of a pair
    is still running when the second character arrives, as when one types fast, and is answered or
    cancelled (`ContentModified`); timed from the second character to the second hover's answer:
    a write that stops the work in flight, then the answer on the new text."""
    await start(session)
    if not session.supports("hover_provider"):
        raise Skipped("no hoverProvider")
    text = session.workspace.subject_text
    names = places.uses(text, session.encoding)
    if not names:
        raise Skipped("nowhere to ask in the subject")
    target = names[len(names) // 2]
    uri = session.open(session.workspace.subject, text)
    await session.hover(uri, *target)
    before = session.usage()

    lines = text.split("\n")
    line, character = len(lines) - 1, column(lines[-1], session.encoding)
    typed = "\nfunc typed(x: Int64): Int64 {\n    x + 1\n}\n"
    latencies, cancelled, version = [], 0, 1

    def type_char(index: int):
        nonlocal line, character, version
        char = typed[index % len(typed)]
        version += 1
        session.insert(uri, version, line, character, char)
        line, character = (line + 1, 0) if char == "\n" else (line, character + 1)

    for i in range(options.keystrokes):
        type_char(2 * i)
        first = session.send_hover(uri, *target)
        began = time.perf_counter()
        type_char(2 * i + 1)
        await session.hover(uri, *target)
        latencies.append((time.perf_counter() - began) * 1000)
        try:
            await asyncio.wait_for(first, session.timeout)
        except JsonRpcException as error:
            if error.code != CONTENT_MODIFIED:
                raise
            cancelled += 1

    after = session.usage()
    return {
        "keystroke_p50_ms": statistics.median(latencies),
        "keystroke_p95_ms": percentile(latencies, 95),
        "keystroke_max_ms": max(latencies),
        "cancelled": cancelled,
        "rss_growth_mb": after.rss_mb - before.rss_mb,
        "cpu_s": after.cpu_s - before.cpu_s,
    }
