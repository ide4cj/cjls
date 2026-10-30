"""The installer selects the host's static stdx even when the parent selects another one."""

import importlib.util
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("setup_cangjie", Path(__file__).with_name("setup.py"))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class EnvironmentTest(unittest.TestCase):
    def test_every_supported_host_exports_its_installed_static_stdx(self):
        for (system, machine), (_, _, directory) in setup.PLATFORMS.items():
            with self.subTest(system=system), \
                    patch.object(setup.platform, "system", return_value=system), \
                    patch.object(setup.platform, "machine", return_value=machine), \
                    patch.dict(os.environ, {"PATH": "/before", "CANGJIE_STDX_PATH": "/other"}, clear=True), \
                    patch.object(setup.subprocess, "run") as run:
                run.return_value.stdout = json.dumps({"PATH": "/sdk/bin" + os.pathsep + "/before"})
                variables, _ = setup.environment("/sdk")
                self.assertEqual(variables["CANGJIE_STDX_PATH"],
                                 os.path.join("/sdk", "third_party", "stdx", directory, "static", "stdx"))
