"""Exercise the real MCP binary interactively, without closing stdin to make it answer."""

import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import unittest


ROOT = Path(__file__).resolve().parents[2]
BINARY = os.environ.get("CJMCP_BIN", str(ROOT / "target/release/bin" / ("cjmcp.exe" if os.name == "nt" else "cjmcp")))


class McpStdioTest(unittest.TestCase):
    def test_analysis_and_disk_reload(self):
        # arrange
        with tempfile.TemporaryDirectory(prefix="cjmcp-") as directory:
            root = Path(directory)
            (root / "src").mkdir()
            (root / "cjpm.toml").write_text(
                '[package]\nname = "sample"\nversion = "0.1.0"\noutput-type = "executable"\n',
                encoding="utf-8", newline="\n",
            )
            (root / "src/helper.cj").write_text(
                "package sample\npublic func shared(): Int64 { 42 }\n", encoding="utf-8", newline="\n",
            )
            source = "package sample\n// привет\npublic func answer(): Int64 { shared() }\nmain() { answer() }\n"
            (root / "src/main.cj").write_text(source, encoding="utf-8", newline="\n")
            process = subprocess.Popen(
                [BINARY, "--dir", str(root)], stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                env={**os.environ, "cjHeapSize": "2GB"},
            )
            replies = queue.Queue()

            def read_replies():
                for line in process.stdout:
                    replies.put(line)
                replies.put(None)

            reader = threading.Thread(target=read_replies, daemon=True)
            reader.start()
            next_id = 0

            def rpc(method, params=None):
                nonlocal next_id
                next_id += 1
                message = {"jsonrpc": "2.0", "id": next_id, "method": method}
                if params is not None:
                    message["params"] = params
                # Split a frame and use CRLF to test the stream boundary, not just JSON parsing.
                wire = json.dumps(message, ensure_ascii=False).encode() + b"\r\n"
                process.stdin.write(wire[:8])
                process.stdin.flush()
                process.stdin.write(wire[8:])
                process.stdin.flush()
                raw = replies.get(timeout=60)
                self.assertIsNotNone(raw, "server closed stdout")
                reply = json.loads(raw)
                self.assertEqual(reply["id"], next_id)
                self.assertNotIn("error", reply)
                return reply["result"]

            def call(name, **arguments):
                result = rpc("tools/call", {"name": name, "arguments": arguments})
                self.assertFalse(result["isError"], result)
                self.assertEqual(json.loads(result["content"][0]["text"]), result["structuredContent"])
                return result["structuredContent"]

            try:
                # act
                init = rpc("initialize", {"protocolVersion": "2025-11-25", "capabilities": {},
                                          "clientInfo": {"name": "test", "version": "1"}})
                process.stdin.write(b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
                process.stdin.flush()
                tools = rpc("tools/list")["tools"]
                status = call("workspace")
                outline = call("file_structure", path="src/main.cj")
                offset = source.encode().rindex(b"answer")
                hover = call("hover", path="src/main.cj", offset=offset)
                definition = call("definition", path="src/main.cj", offset=offset)
                diagnostics = call("diagnostics", path="src/main.cj")
                cross_file = call("definition", path="src/main.cj", offset=source.encode().index(b"shared"))

                # assert
                self.assertEqual(init["protocolVersion"], "2025-11-25")
                self.assertEqual(len(tools), 6)
                self.assertIn(root / "src/main.cj", list(map(Path, status["files"])))
                self.assertFalse(status["macrosExpanded"])
                self.assertIn("answer", [symbol["name"] for symbol in outline["symbols"]])
                self.assertIn("answer", hover["hover"]["items"][0]["code"])
                target = definition["targets"][0]
                self.assertEqual(Path(target["path"]), root / "src/main.cj")
                selection = target["selectionRange"]
                self.assertEqual(source.encode()[selection["start"]:selection["end"]], b"answer")
                self.assertEqual(diagnostics["diagnostics"], [])
                self.assertEqual(Path(cross_file["targets"][0]["path"]), root / "src/helper.cj")

                # act - an invalid byte offset, then a new file, an edit and a deletion on disk
                invalid = rpc("tools/call", {"name": "hover", "arguments": {
                    "path": "src/main.cj", "offset": source.encode().index("п".encode()) + 1}})
                (root / "src/main.cj").write_text("package sample\nmain() { let value: Int64 = true }\n", encoding="utf-8", newline="\n")
                (root / "src/new.cj").write_text("package sample\npublic func added() {}\n", encoding="utf-8", newline="\n")
                call("reload_workspace")
                changed = call("diagnostics", path="src/main.cj")
                added = call("file_structure", path="src/new.cj")
                (root / "src/new.cj").unlink()
                after_delete = call("reload_workspace")

                # assert
                self.assertTrue(invalid["isError"])
                self.assertTrue(any("mismatched types" in item["message"] for item in changed["diagnostics"]))
                self.assertIn("added", [symbol["name"] for symbol in added["symbols"]])
                self.assertNotIn(root / "src/new.cj", list(map(Path, after_delete["files"])))
            finally:
                process.stdin.close()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                stderr = process.stderr.read().decode(errors="replace")
                process.stdout.close()
                process.stderr.close()
                reader.join(timeout=5)
            self.assertEqual(process.returncode, 0, stderr)


if __name__ == "__main__":
    unittest.main()
