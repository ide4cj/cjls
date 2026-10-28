"""Text scenarios inspired by cangjie_test_framework's comment directives.

Each step is a complete workspace snapshot; only changed text is sent over LSP.
Source markers are removed before either consumer sees the text.
"""

import copy
from pathlib import PurePosixPath
import re


DIRECTIVE = re.compile(r"^// ([A-Z][A-Z-]*): ?(.*)$")
MARKER = re.compile(r"/\*@(/?)([a-zA-Z][a-zA-Z0-9_]*)\*/")
NAME = re.compile(r"[a-zA-Z][a-zA-Z0-9_]*\Z")
SEVERITY = {"error": 1, "warning": 2}


def relative_path(value, allow_dot=False):
    """Accept portable workspace-relative paths, never platform-specific escapes."""
    path = PurePosixPath(value)
    if (not value or "\\" in value or ":" in value or path.is_absolute()
            or ".." in path.parts or str(path) != value
            or (value == "." and not allow_dot)):
        raise ValueError(f"invalid relative path: {value!r}")
    return value


def source_markers(text):
    """Return unmarked source and named, half-open UTF-16 ranges (including points)."""
    chunks, starts, spans = [], {}, {}
    line = column = offset = 0
    for marker in MARKER.finditer(text):
        chunk = text[offset:marker.start()]
        chunks.append(chunk)
        pieces = chunk.split("\n")
        if len(pieces) > 1:
            line += len(pieces) - 1
            column = 0
        column += len(pieces[-1].encode("utf-16-le")) // 2
        closing, name = marker.groups()
        if closing:
            if name not in starts:
                raise ValueError(f"unopened source marker: {name}")
            spans[name] = [*starts.pop(name), line, column]
        else:
            if name in starts or name in spans:
                raise ValueError(f"duplicate source marker: {name}")
            starts[name] = [line, column]
        offset = marker.end()
    if starts:
        raise ValueError(f"unclosed source markers: {sorted(starts)}")
    chunks.append(text[offset:])
    return "".join(chunks), spans


def parse_scenario(text, ident, read_source):
    """Parse a runner header or .info descriptor with a fixture-relative source loader."""
    case = {"id": ident, "issue": None, "packages": [], "steps": []}
    step = None
    file = None
    source = []
    expectations = []
    touched = set()
    block_comment = False

    def finish_file():
        nonlocal file, source, expectations
        if file is None:
            return
        clean, spans = source_markers("".join(source))
        step["files"][file] = clean
        step["expected"] = [d for d in step["expected"] if d["file"] != file]
        for name, span, severity, message in expectations:
            if span not in spans:
                raise ValueError(f"unknown source marker: {span}")
            step["expected"].append({"id": name, "file": file, "range": spans[span],
                                     "severity": SEVERITY[severity], "message": message})
        file, source, expectations = None, [], []

    def finish_step():
        finish_file()
        if step is not None:
            previous = case["steps"][-1]["files"] if case["steps"] else {}
            step["changes"] = {path: value for path, value in step["files"].items()
                               if previous.get(path) != value}
            step["deleted"] = sorted(previous.keys() - step["files"].keys())
            case["steps"].append(step)

    for number, raw in enumerate(text.splitlines(keepends=True), 1):
        try:
            if block_comment or raw.lstrip().startswith("/*"):
                block_comment = "*/" not in raw
                if not block_comment and raw.split("*/", 1)[1].strip():
                    raise ValueError("source after a descriptor block comment")
                continue
            match = DIRECTIVE.fullmatch(raw.rstrip("\r\n"))
            if not match:
                if raw.strip() and not raw.startswith("//"):
                    raise ValueError("put Cangjie source in a .cj file, not the descriptor")
                continue
            key, value = match.groups()
            if key == "ISSUE" and step is None and case["issue"] is None:
                case["issue"] = int(value)
            elif key == "PACKAGE" and step is None:
                parts = value.split()
                if len(parts) not in (2, 3) or not NAME.fullmatch(parts[0]):
                    raise ValueError("PACKAGE needs a name, project directory and optional depends=a,b")
                dependencies = []
                if len(parts) == 3:
                    if not parts[2].startswith("depends="):
                        raise ValueError("expected depends=a,b")
                    dependencies = parts[2][8:].split(",")
                case["packages"].append({"name": parts[0],
                                          "root": relative_path(parts[1], allow_dot=True),
                                          "dependencies": dependencies})
            elif key == "PLATFORMS" and step is None:
                case["platforms"] = value.split()
            elif key == "SKIP-REASON" and step is None:
                case["skip_reason"] = value
            elif key == "STEP":
                finish_step()
                parts = value.split()
                if len(parts) not in (1, 3) or not NAME.fullmatch(parts[0]):
                    raise ValueError("STEP needs a name or name FROM earlier_step")
                if any(s["name"] == parts[0] for s in case["steps"]):
                    raise ValueError("duplicate step name")
                if len(parts) == 3:
                    if parts[1] != "FROM":
                        raise ValueError("expected FROM earlier_step")
                    origin = next((s for s in case["steps"] if s["name"] == parts[2]), None)
                    if origin is None:
                        raise ValueError("unknown earlier step")
                    step = copy.deepcopy(origin)
                else:
                    origin = case["steps"][-1] if case["steps"] else {}
                    step = {"files": copy.deepcopy(origin.get("files", {})),
                            "expected": copy.deepcopy(origin.get("expected", [])), "compiler": {}}
                step["name"] = parts[0]
                touched = set()
            elif key == "SOURCE" and step is not None:
                finish_file()
                destination, reference = value.split()
                file = relative_path(destination)
                if not file.endswith(".cj") or file in touched:
                    raise ValueError("SOURCE needs a unique workspace .cj path in this step")
                touched.add(file)
                source = [read_source(reference)]
            elif key == "DELETE-FILE" and step is not None:
                finish_file()
                path = relative_path(value)
                if path not in step["files"] or path in touched:
                    raise ValueError("DELETE-FILE needs an existing, untouched path")
                touched.add(path)
                del step["files"][path]
                step["expected"] = [d for d in step["expected"] if d["file"] != path]
            elif key == "EXPECT" and file is not None:
                match = re.fullmatch(r"(\w+) (\w+) (error|warning): (.+)", value)
                if not match:
                    raise ValueError("EXPECT needs diagnostic_id marker_id error|warning: message")
                expectations.append(match.groups())
            elif key == "CJC" and step is not None:
                finish_file()
                package, contract = value.split(" ", 1)
                if contract == "clean":
                    if package in step["compiler"]:
                        raise ValueError("duplicate clean compiler contract")
                    step["compiler"][package] = []
                else:
                    severity, message = contract.split(": ", 1)
                    if severity not in SEVERITY or not message:
                        raise ValueError("CJC needs package clean|error: message|warning: message")
                    if package in step["compiler"] and not step["compiler"][package]:
                        raise ValueError("clean compiler contract cannot also have diagnostics")
                    step["compiler"].setdefault(package, []).append(
                        {"severity": severity, "message": message})
            else:
                raise ValueError(f"unexpected directive: {key}")
        except (ValueError, KeyError, OSError) as error:
            raise ValueError(f"{ident}:{number}: {error}") from error
    if block_comment:
        raise ValueError(f"{ident}: unclosed descriptor block comment")
    finish_step()
    validate_scenario(case)
    return case


def validate_scenario(case):
    if not isinstance(case["issue"], int) or case["issue"] <= 0:
        raise ValueError(f"{case['id']}: missing issue attribution")
    if not case["packages"] or not case["steps"]:
        raise ValueError(f"{case['id']}: needs packages and steps")
    if "platforms" in case and (not case["platforms"] or not case.get("skip_reason")):
        raise ValueError(f"{case['id']}: platform applicability needs a skip reason")
    names, roots = set(), set()
    for package in case["packages"]:
        if package["name"] in names or package["root"] in roots:
            raise ValueError(f"{case['id']}: duplicate package name or directory")
        if set(package["dependencies"]) - names:
            raise ValueError(f"{case['id']}: declare dependencies before their consumers")
        names.add(package["name"])
        roots.add(package["root"])
    # One explicit package per project; nested package projects would overwrite manifests.
    if any(a != b and PurePosixPath(a) in PurePosixPath(b).parents for a in roots for b in roots):
        raise ValueError(f"{case['id']}: package project directories must not overlap")
    directories = {str(PurePosixPath(root) / "src") for root in roots}
    for step in case["steps"]:
        if set(step["compiler"]) != names:
            raise ValueError(f"{case['id']}/{step['name']}: needs one CJC contract per package")
        parents = {str(PurePosixPath(path).parent) for path in step["files"]}
        if parents != directories:
            raise ValueError(f"{case['id']}/{step['name']}: files must belong to declared packages' src directories")
        ids = [d["id"] for d in step["expected"]]
        if len(set(ids)) != len(ids):
            raise ValueError(f"{case['id']}/{step['name']}: duplicate diagnostic IDs")
    rejected = any(d["severity"] == "error" for step in case["steps"]
                   for contract in step["compiler"].values() for d in contract)
    corrected = any(not step["expected"] and all(not contract for contract in step["compiler"].values())
                    for step in case["steps"])
    if rejected and not corrected:
        raise ValueError(f"{case['id']}: rejected scenario needs a clean corrected control")


def split_header(text):
    """Separate leading comments (including license blocks) from a native source body."""
    lines = text.splitlines(keepends=True)
    end = 0
    block_comment = False
    while end < len(lines):
        line = lines[end].lstrip()
        if block_comment or line.startswith("/*"):
            if "*/" in line and line.split("*/", 1)[1].strip():
                break
            block_comment = "*/" not in line
        elif line.strip() and not line.startswith("//"):
            break
        end += 1
    return "".join(lines[:end]), "".join(lines[end:])


def fixture_files(folder):
    """All descriptors and native sources, including auxiliary inputs, for evidence hashes."""
    return sorted(path for path in folder.rglob("*") if path.suffix in (".cj", ".info"))


def load_scenarios(folder):
    """Discover .info descriptors and .cj runner headers; auxiliary sources are not tests."""
    cases, ids = [], set()
    for path in fixture_files(folder):
        text = path.read_text(encoding="utf-8")
        header, body = split_header(text)
        if path.suffix == ".cj" and not any(DIRECTIVE.fullmatch(line) for line in header.splitlines()):
            continue
        ident = path.relative_to(folder).with_suffix("").as_posix()
        if ident in ids:
            raise ValueError(f"{ident}: both .cj and .info define the same scenario")
        ids.add(ident)

        def read_source(reference):
            if reference == "%f":
                if path.suffix != ".cj":
                    raise ValueError("%f requires a .cj runner header")
                return body
            relative_path(reference)
            source_path = path.parent / reference
            if source_path.suffix != ".cj" or not source_path.resolve().is_relative_to(path.parent.resolve()):
                raise ValueError(f"source must be a fixture-relative .cj file: {reference}")
            return source_path.read_text(encoding="utf-8")

        cases.append(parse_scenario(header if path.suffix == ".cj" else text, ident, read_source))
    return cases
