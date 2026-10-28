"""Integration regression; set CJLS_BIN and CJFMT_BIN to built formatter executables.

Run with python3 -m unittest discover -s tests/perf -p 'formatter_cli_test.py'.
"""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class FormatterCliTest(unittest.TestCase):
    def test_parent_policy_cannot_change_comparison(self):
        # arrange
        cjls = Path(os.environ["CJLS_BIN"]).resolve(strict=True)
        cjfmt = Path(os.environ["CJFMT_BIN"]).resolve(strict=True)
        script = Path(__file__).with_name("formatter_cli.py")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "cjformat.toml").write_text("unknown_setting = true\n")
            source = root / "original.cj"
            original = b"func f() { let x = if (true) { 1 } else { 2 } }\n"
            source.write_bytes(original)
            for inputs in [["--sizes", "1"], ["--inputs", str(source)]]:
                with self.subTest(inputs=inputs):
                    output = root / "results" / "report.json"

                    # act
                    result = subprocess.run(
                        [sys.executable, str(script), "--cjls", str(cjls),
                         "--cjfmt", str(cjfmt), "--output", str(output),
                         "--repetitions", "2", "--warmup", "0", *inputs],
                        capture_output=True, text=True, timeout=60,
                    )

                    # assert
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    report = json.loads(output.read_text())
                    self.assertEqual(report["formatter_options"]["cjls"], {
                        "line_width": 100, "indent_width": 4, "simple_if": "multiline",
                    })
                    self.assertEqual(report["formatter_options"]["cjfmt"], {
                        "indentWidth": 4, "linelimitLength": 100, "lineBreakType": "LF",
                    })
                    self.assertEqual(source.read_bytes(), original)
                    self.assertEqual(len(report["cases"]), 1)
                    for tool in ["cjls", "cjfmt"]:
                        self.assertEqual(len(report["cases"][0]["results"][tool]["samples_ms"]), 2)
                    if inputs[0] == "--inputs":
                        self.assertEqual(report["cases"][0]["input_sha256"],
                                         hashlib.sha256(original).hexdigest())
                        expected = (b"func f() {\n    let x =\n        if (true) {\n"
                                    b"            1\n        } else {\n            2\n        }\n}\n")
                        self.assertEqual(report["cases"][0]["results"]["cjls"]["output_sha256"],
                                         hashlib.sha256(expected).hexdigest())
