package cjmcp

// Presentation only: semantic selection stays in loupe and the task script.
@When[os == "Linux"]
const PYTHON_EVIDENCE =
    #"

import bisect as _cjmcp_bisect


def exact_symbols(analysis, paths, name):
    """Select all case-sensitive exact file-symbol matches in explicit paths.
    No fuzzy limit is applied. Dependencies are included only when paths include them.
    Return native symbols with paths; project fields before returning JSON.
    """
    return [(path, symbol) for path in dict.fromkeys(paths)
            for symbol in analysis.fileSymbols(path) if symbol.name == name]

def result_page(rows, *, offset=0, limit=20):
    """Bound projected rows, retaining totals and a continuation offset.
    This is a row limit, not a byte budget; source_excerpts bounds source bytes.
    """
    rows = list(rows)
    if type(offset) is not int or not 0 <= offset <= len(rows):
        raise ValueError('offset must be within rows')
    if type(limit) is not int or limit < 1:
        raise ValueError('limit must be a positive integer')
    selected = rows[offset:offset + limit]
    end = offset + len(selected)
    return dict(rows=selected, total=len(rows), returned=len(selected),
                omitted=len(rows)-len(selected), offset=offset,
                next_offset=end if end < len(rows) else None)

def declaration_range(analysis, path, selection, kind):
    """Return a written declaration range including enclosing macro annotations.
    selection is its name range; kind is the exact syntax kind, e.g. FuncDecl.
    Reject absent/ambiguous syntax. Comments/trivia outside the node stay untouched.
    Recompute after edits; never use expanded-source or display-context ranges.
    """
    tree = analysis.semantic().syntaxAt(analysis.fileId(path))
    if tree is None:
        raise ValueError('source syntax unavailable')
    nodes = [node for node in tree.root().descendants()
             if node.kindName() == kind
             and any(child.kindName() == 'Name'
                     and child.location().fullRange.start == selection.start
                     and child.location().fullRange.end == selection.end
                     for child in node.children())]
    if not nodes:
        raise ValueError('no enclosing declaration of the selected kind')
    width = min(node.location().fullRange.len for node in nodes)
    nodes = [node for node in nodes if node.location().fullRange.len == width]
    if len(nodes) != 1:
        raise ValueError('ambiguous declaration syntax')
    node = nodes[0]
    parent = node.parent()
    while parent is not None and parent.kindName() == 'MacroExpandDecl':
        node, parent = parent, parent.parent()
    return node.location().fullRange

def source_excerpts(analysis, requests, *, max_bytes=12000, offset=0, limit=20, context_lines=0):
    """Page (path, UTF-8 TextRange) requests without cutting any excerpt.
    max_bytes covers the complete returned JSON, encoded as compact UTF-8.
    Lines are one-based/inclusive; byte ranges are zero-based/end-exclusive.
    Oversized entries stop the page: narrow the range or raise max_bytes.
    """
    if type(max_bytes) is not int or max_bytes < 256:
        raise ValueError('max_bytes must be an integer >= 256')
    requests = list(requests)
    if type(offset) is not int or not 0 <= offset <= len(requests):
        raise ValueError('offset must be within requests')
    if type(limit) is not int or limit < 1:
        raise ValueError('limit must be a positive integer')
    if type(context_lines) is not int or context_lines < 0:
        raise ValueError('context_lines must be a nonnegative integer')
    cache = {}
    entries = []
    total = len(requests)

    def page(required_bytes=None):
        next_offset = offset + len(entries)
        return dict(revision=analysis.revision, total=total, offset=offset,
                    returned=len(entries), omitted=total-len(entries),
                    next_offset=next_offset if next_offset < total else None,
                    required_bytes=required_bytes, excerpts=list(entries))

    for index in range(offset, min(total, offset + limit)):
        path, span = requests[index]
        if path not in cache:
            data = analysis.text(path).encode('utf-8')
            starts = [0] + [i + 1 for i, byte in enumerate(data) if byte == 10]
            cache[path] = data, starts
        data, starts = cache[path]
        start, end = span.start, span.end
        if not 0 <= start <= end <= len(data):
            raise ValueError('range must be within the file')
        # Strict decoding checks both boundaries, even for an empty range.
        data[:start].decode('utf-8')
        data[start:end].decode('utf-8')
        first = _cjmcp_bisect.bisect_right(starts, start) - 1
        last = _cjmcp_bisect.bisect_right(starts, max(start, end - 1)) - 1
        shown_start, shown_end = start, end
        if context_lines:
            first = max(0, first - context_lines)
            last = min(len(starts) - 1, last + context_lines)
            shown_start = starts[first]
            shown_end = starts[last + 1] if last + 1 < len(starts) else len(data)
        entry = dict(index=index, path=path, range=dict(start=start, end=end),
                     shown_range=dict(start=shown_start, end=shown_end),
                     start_line=first + 1, end_line=last + 1,
                     source=data[shown_start:shown_end].decode('utf-8'))
        entries.append(entry)
        candidate = page()
        size = len(_cjmcp_json.dumps(candidate, ensure_ascii=False, separators=(',', ':')).encode('utf-8'))
        if size > max_bytes:
            entries.pop()
            # Size needed to include the blocked entry with the already selected prefix.
            required = size
            answer = page(required)
            # Metadata growth can itself exhaust an exact-fit budget. Remove whole
            # entries, never bytes, until the complete page fits.
            while len(_cjmcp_json.dumps(answer, ensure_ascii=False, separators=(',', ':')).encode('utf-8')) > max_bytes:
                if not entries:
                    raise ValueError('max_bytes too small for page metadata; increase it')
                entries.pop()
                answer = page(required)
            return answer
    return page()
"#
