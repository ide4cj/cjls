"""Where the navigation scenarios ask: names in the subject's code, found by a scan that knows
comments and strings, not by a parser, so that it works on any workspace and for any server."""

import bisect
import re

from .session import column

IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
MEMBER_DOT = re.compile(r"(?<=[A-Za-z0-9_)\]])\.(?=[A-Za-z_])")
# a name right after one of these is declared there, not used: asking where it is declared is moot
DECLARING = {"func", "class", "struct", "interface", "enum", "let", "var", "const", "prop", "type", "macro", "package", "import"}
KEYWORDS = DECLARING | {
    "public", "private", "protected", "internal", "open", "override", "redef", "static", "mut", "abstract", "sealed",
    "unsafe", "foreign", "operator", "extend", "init", "this", "super", "return", "if", "else", "match", "case",
    "for", "in", "while", "do", "try", "catch", "finally", "throw", "where", "true", "false", "is", "as", "spawn",
    "synchronized", "quote", "break", "continue", "main", "Unit", "Nothing",
}


def code_spans(text: str) -> list[tuple[int, int]]:
    """The subject's code as offset ranges: comments and string literals left out."""
    spans, start, i, n = [], 0, 0, len(text)
    while i < n:
        if text.startswith("//", i):
            end = text.find("\n", i)
            end = n if end < 0 else end
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            end = n if end < 0 else end + 2
        elif text.startswith('"""', i) or text.startswith("'''", i):
            end = text.find(text[i : i + 3], i + 3)
            end = n if end < 0 else end + 3
        elif text[i] in "\"'":
            end = i + 1
            while end < n and text[end] != text[i] and text[end] != "\n":
                end += 2 if text[end] == "\\" else 1
            end = min(n, end + 1)
        else:
            i += 1
            continue
        spans.append((start, i))
        start = i = end
    spans.append((start, n))
    return spans


def line_starts(text: str) -> list[int]:
    return [0] + [match.end() for match in re.finditer("\n", text)]


def place(text: str, starts: list[int], offset: int, encoding: str) -> tuple[int, int] | None:
    """`offset` as (line, column), `None` on a `package` or `import` line."""
    line = bisect.bisect_right(starts, offset) - 1
    head = text[starts[line] : offset]
    if head.lstrip().startswith(("package ", "import ")):
        return None
    return line, column(head, encoding)


def uses(text: str, encoding: str) -> list[tuple[int, int]]:
    """Every name used in the subject's code, at its middle: go to definition and hover ask there."""
    found, starts = [], line_starts(text)
    for begin, end in code_spans(text):
        previous = None
        for match in IDENTIFIER.finditer(text, begin, end):
            name = match.group()
            declared, previous = previous in DECLARING, name
            if name in KEYWORDS or declared:
                continue
            at = place(text, starts, match.start() + len(name) // 2, encoding)
            if at:
                found.append(at)
    return found


def members(text: str, encoding: str) -> list[tuple[int, int]]:
    """Every place right after a `.` that selects a member (`a.b`, `f().b`): where completion is
    asked as one starts typing the member's name."""
    found, starts = [], line_starts(text)
    for begin, end in code_spans(text):
        for match in MEMBER_DOT.finditer(text, begin, end):
            at = place(text, starts, match.end(), encoding)
            if at:
                found.append(at)
    return found


def spread(candidates: list, count: int) -> list:
    """`count` of `candidates`, spread evenly over them: the same every run."""
    if len(candidates) <= count:
        return candidates
    if count == 1:
        return candidates[:1]
    return [candidates[round(k * (len(candidates) - 1) / (count - 1))] for k in range(count)]
