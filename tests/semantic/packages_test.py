"""Cross-package compiler isolation and unchanged-consumer edit regressions."""

import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import AsyncMock, patch

from oracle import apply_step, compile_step
from scenarios import load_scenarios
from scenarios_test import RecordingLsp


class PackageTest(unittest.IsolatedAsyncioTestCase):
    async def test_compiler_imports_transitive_dependencies_without_unrelated_packages(self):
        # arrange
        case = next(case for case in load_scenarios(Path(__file__).parent / "cases")
                    if case["id"] == "package_transitive_inference")
        case = copy.deepcopy(case)
        case["packages"].insert(0, {"name": "unrelated", "root": "unrelated", "dependencies": []})
        step = case["steps"][1]
        step["files"]["unrelated/src/main.cj"] = "package unrelated\n"
        step["compiler"]["unrelated"] = []
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            command = AsyncMock(return_value=(0, "", ""))

            # act
            with patch("oracle.command", command):
                results = await compile_step(case, step, output / "sdk", output, {}, 30)
            app = next(result for result in results if result["package"] == "app")
            libraries = [argument for argument in app["command"] if argument.startswith("-l")]

            # assert
            self.assertEqual([result["package"] for result in results],
                             ["unrelated", "api", "bridge", "app"])
            self.assertEqual(libraries, ["-lapi", "-lbridge"])
            self.assertTrue(all("failure" not in result for result in results))

    async def test_provider_repairs_do_not_send_consumer_edits(self):
        # arrange
        cases = load_scenarios(Path(__file__).parent / "cases")
        names = {"package_visibility_private", "package_visibility_internal",
                 "package_visibility_protected", "package_transitive_inference",
                 "package_extend_interface_members", "package_extend_plain"}
        for case in (case for case in cases if case["id"] in names):
            with self.subTest(case=case["id"]), tempfile.TemporaryDirectory() as folder:
                broken, fixed = case["steps"][:2]
                rpc = RecordingLsp()

                # act
                await apply_step(rpc, Path(folder), broken["files"], fixed, 2)
                edits = [message["params"]["uri"] for message in rpc.messages]

                # assert
                self.assertTrue(edits)
                self.assertTrue(all("/app/" not in uri for uri in edits))
                self.assertEqual(fixed["expected"], [])
                self.assertTrue(all(message["method"] == "textDocument/didChange"
                                    for message in rpc.messages))
