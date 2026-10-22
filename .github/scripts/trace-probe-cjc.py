#!/usr/bin/env python3
"""Record actual compiler arguments while preserving the descriptor-closing shim."""

import json
import os
from pathlib import Path
import sys
import time


trace = Path(os.environ["PROBE_CJC_TRACE"])
trace.mkdir(parents=True, exist_ok=True)
(trace / f"{os.getpid()}-{time.time_ns()}.json").write_text(json.dumps({
    "cwd": os.getcwd(), "args": sys.argv[1:],
}))
cjc = str(Path(os.environ["CANGJIE_HOME"]) / "bin" / "cjc")
os.closerange(3, os.sysconf("SC_OPEN_MAX"))
os.execv(cjc, [cjc, *sys.argv[1:]])
