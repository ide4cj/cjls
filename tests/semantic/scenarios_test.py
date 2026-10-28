"""Scenario parsing, coordinate mapping and document lifecycle regressions."""

import argparse
import contextlib
import copy
import io
from pathlib import Path
import tempfile
import textwrap
import unittest
from unittest.mock import AsyncMock, patch

from oracle import apply_step, compile_step, prepare_workspace, read_json, run
from scenarios import load_scenarios, parse_scenario as parse_descriptor, relative_path, source_markers


SIMPLE = """\
// ISSUE: 528
// PACKAGE: audit .
// STEP: initial
// CJC: audit clean
// SOURCE: src/main.cj main.cj
"""
SOURCES = {
    'main.cj': 'package audit\nfunc f(): Int64 { 1 }\n',
    'marked.cj': 'package audit\nfunc f(): Int64 { /*@result*/1/*@/result*/ }\n',
    'other.cj': 'package audit\nlet value = /*@value*/1/*@/value*/\n',
}


def parse_scenario(text, ident):
    return parse_descriptor(text, ident, SOURCES.__getitem__)


class ScenarioTest(unittest.TestCase):
    def test_markers_preserve_source_and_map_utf16_multiline_points_and_overlaps(self):
        # arrange
        text = 'let x = "😀"; /*@outer*/a/*@inner*/b\nc/*@/outer*/d/*@/inner*//*@point*//*@/point*/\n'

        # act
        source, spans = source_markers(text)

        # assert
        self.assertEqual(source, 'let x = "😀"; ab\ncd\n')
        self.assertEqual(spans, {"outer": [0, 14, 1, 1], "inner": [0, 15, 1, 2],
                                 "point": [1, 2, 1, 2]})

    def test_broken_markers_fail(self):
        # arrange
        examples = ('/*@a*/x', '/*@/a*/', '/*@a*//*@a*/x/*@/a*/', '/*@a*/x/*@/a*//*@a*/y/*@/a*/')
        for text in examples:
            with self.subTest(text=text):
                # act / assert
                with self.assertRaises(ValueError):
                    source_markers(text)

    def test_nonportable_and_escaping_paths_fail(self):
        # arrange
        paths = ('../x.cj', '/x.cj', 'C:/x.cj', 'src\\x.cj', 'src/../x.cj', './src/x.cj', '')
        for path in paths:
            with self.subTest(path=path):
                # act / assert
                with self.assertRaises(ValueError):
                    relative_path(path)

    def test_unchanged_source_replaces_expectations_without_becoming_an_edit(self):
        # arrange
        text = SIMPLE.replace('main.cj\n', 'marked.cj\n')
        text += '// EXPECT: result result warning: example\n'
        text += '// STEP: next\n// CJC: audit clean\n// SOURCE: src/main.cj main.cj\n'
        text += '// STEP: restored FROM initial\n'

        # act
        case = parse_scenario(text, 'same_source')
        initial, changed, restored = case['steps']

        # assert
        self.assertEqual(changed['changes'], {})
        self.assertEqual(changed['expected'], [])
        self.assertEqual(restored['changes'], {})
        self.assertEqual(restored['expected'], initial['expected'])
        restored['expected'][0]['message'] = 'changed'
        self.assertEqual(initial['expected'][0]['message'], 'example')

    def test_arbitrary_step_sequence_adds_deletes_and_restores_files(self):
        # arrange
        text = SIMPLE + textwrap.dedent('''\
            // STEP: added
            // CJC: audit clean
            // SOURCE: src/other.cj other.cj
            // STEP: removed
            // CJC: audit clean
            // DELETE-FILE: src/other.cj
            // STEP: restored FROM added
            ''')

        # act
        case = parse_scenario(text, 'lifecycle')

        # assert
        self.assertEqual(list(case['steps'][1]['changes']), ['src/other.cj'])
        self.assertEqual(case['steps'][2]['deleted'], ['src/other.cj'])
        self.assertEqual(case['steps'][3]['files'], case['steps'][1]['files'])

    def test_malformed_directives_and_stale_references_fail_before_execution(self):
        # arrange
        examples = [
            SIMPLE.replace('// CJC: audit clean\n', ''),
            SIMPLE.replace('// CJC: audit clean\n', '// CJC: audit clean\n// CJC: audit warning: example\n'),
            SIMPLE.replace('// CJC:', '// CJJ:'),
            SIMPLE + '// EXPECT: d missing error: problem\n',
            SIMPLE + '// STEP: restored FROM missing\n',
            SIMPLE + '// STEP: initial\n',
            SIMPLE + '// DELETE-FILE: src/absent.cj\n',
            SIMPLE + '// SOURCE: src/main.cj main.cj\n',
            SIMPLE.replace('src/main.cj', 'other/main.cj'),
            SIMPLE.replace('audit clean', 'audit error: problem'),
            SIMPLE.replace('// ISSUE: 528\n', ''),
            SIMPLE.replace('// PACKAGE: audit .', '// PACKAGE: audit . depends=absent'),
        ]
        for text in examples:
            with self.subTest(text=text):
                # act / assert
                with self.assertRaises(ValueError):
                    parse_scenario(text, 'malformed')

    def test_diagnostics_can_belong_to_any_file(self):
        # arrange
        text = SIMPLE + textwrap.dedent('''\
            // SOURCE: src/other.cj other.cj
            // EXPECT: other value warning: example
            ''')

        # act
        case = parse_scenario(text, 'other')

        # assert
        self.assertEqual(case['steps'][0]['expected'][0]['file'], 'src/other.cj')

    def test_discovery_keeps_directory_in_case_id(self):
        # arrange
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            (path / 'nested').mkdir()
            (path / 'nested' / 'example.info').write_text(SIMPLE)
            (path / 'nested' / 'main.cj').write_text(SOURCES['main.cj'])

            # act
            cases = load_scenarios(path)

            # assert
            self.assertEqual(cases[0]['id'], 'nested/example')

    def test_native_header_and_info_produce_the_same_model(self):
        # arrange
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            native, separate = root / 'native', root / 'separate'
            native.mkdir()
            separate.mkdir()
            source = SOURCES['marked.cj']
            header = SIMPLE.replace('main.cj main.cj', 'main.cj %f')
            header += '// EXPECT: result result warning: example\n'
            license = '/*\n * Example license header.\n */\n'
            (native / 'example.cj').write_text(license + header + source)
            (separate / 'example.info').write_text(license + header.replace('%f', 'input.cj'))
            (separate / 'input.cj').write_text(source)

            # act
            inline = load_scenarios(native)
            sidecar = load_scenarios(separate)

            # assert
            self.assertEqual(inline, sidecar)
            self.assertEqual(len(sidecar), 1)
            self.assertEqual(inline[0]['steps'][0]['files']['src/main.cj'], SOURCES['main.cj'])

    def test_duplicate_entry_forms_fail_instead_of_running_twice(self):
        # arrange
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'example.cj').write_text(SIMPLE.replace('main.cj main.cj', 'main.cj %f')
                                           + SOURCES['main.cj'])
            (root / 'example.info').write_text(SIMPLE)
            (root / 'main.cj').write_text(SOURCES['main.cj'])

            # act / assert
            with self.assertRaisesRegex(ValueError, 'same scenario'):
                load_scenarios(root)

    def test_invalid_external_sources_and_inline_info_code_fail(self):
        # arrange
        for reference in ('%f', '../main.cj', 'missing.cj', 'other.info'):
            with self.subTest(reference=reference), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                (root / 'example.info').write_text(SIMPLE.replace('main.cj main.cj',
                                                                 f'main.cj {reference}'))

                # act / assert
                with self.assertRaises(ValueError):
                    load_scenarios(root)
        # arrange
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'example.info').write_text(SIMPLE + SOURCES['main.cj'])
            (root / 'main.cj').write_text(SOURCES['main.cj'])

            # act / assert
            with self.assertRaisesRegex(ValueError, 'put Cangjie source'):
                load_scenarios(root)

    def test_known_directives_require_live_references_and_issue(self):
        # arrange
        for directive in ("KNOWN-MISSING: absent issue=528", "KNOWN-MISSING: d issue=0",
                          "KNOWN-EXTRA: absent issue=528 error: example"):
            with self.subTest(directive=directive):
                text = SIMPLE + "// " + directive + "\n"

                # act / assert
                with self.assertRaises(ValueError):
                    parse_scenario(text, "invalid")

    def test_known_differences_follow_source_replacement_deletion_and_restore(self):
        # arrange
        text = SIMPLE.replace("main.cj\n", "marked.cj\n")
        text += "// EXPECT: d result error: example\n// KNOWN-MISSING: d issue=529\n"
        text += "// KNOWN-EXTRA: result issue=544 warning: extra\n"
        text += "// STEP: fixed\n// CJC: audit clean\n// SOURCE: src/main.cj main.cj\n"
        text += "// STEP: restored FROM initial\n"
        text += "// STEP: deleted\n// CJC: audit clean\n// DELETE-FILE: src/main.cj\n"
        text += "// SOURCE: src/other.cj other.cj\n"

        # act
        case = parse_scenario(text, "known")

        # assert
        initial, fixed, restored, deleted = case["steps"]
        self.assertEqual(initial["known"], restored["known"])
        self.assertEqual(fixed["known"], {"missing": [], "extra": []})
        self.assertEqual(deleted["known"], {"missing": [], "extra": []})
        self.assertEqual(initial["known"]["extra"][0]["range"], [1, 18, 1, 19])

    def test_dependency_projects_have_real_manifests_and_all_initial_files(self):
        # arrange
        folder = Path(__file__).parent / 'cases'
        case = next(case for case in load_scenarios(folder) if case['id'] == 'package_dependency')
        with tempfile.TemporaryDirectory() as folder:
            workspace = Path(folder)

            # act
            initial = prepare_workspace(case, workspace)

            # assert
            self.assertEqual(len(initial), 3)
            self.assertIn('members = ["api", "app"]', (workspace / 'cjpm.toml').read_text())
            self.assertIn('api = { path = "../api" }', (workspace / 'app/cjpm.toml').read_text())
            self.assertEqual((workspace / 'api/src/helper.cj').read_text(), 'package api\n')


class RecordingLsp:
    def __init__(self):
        self.messages = []

    async def send(self, **message):
        self.messages.append(message)

    async def change(self, path, source, version):
        await self.send(method='textDocument/didChange', params={
            'uri': path.as_uri(), 'text': source, 'version': version})


class EditTest(unittest.IsolatedAsyncioTestCase):
    async def test_invalid_selection_keeps_a_failure_report_without_starting_processes(self):
        # arrange
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'evidence'
            args = argparse.Namespace(output=output, case=['does_not_exist'])

            # act
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                status = await run(args)
            report = read_json(output / 'report.json')

            # assert
            self.assertEqual(status, 1)
            self.assertEqual(report['status'], 'failed')
            self.assertIn('unknown --case ID', report['failures'][0])
            self.assertEqual(report['cases'], [])

    async def test_cross_file_edit_does_not_touch_the_requesting_document(self):
        # arrange
        case = next(case for case in load_scenarios(Path(__file__).parent / 'cases')
                    if case['id'] == 'cross_file_return')
        broken, fixed, restored = case['steps']
        rpc = RecordingLsp()
        with tempfile.TemporaryDirectory() as folder:
            workspace = Path(folder)

            # act
            await apply_step(rpc, workspace, broken['files'], fixed, 2)
            await apply_step(rpc, workspace, fixed['files'], restored, 3)

            # assert
            self.assertEqual([message['method'] for message in rpc.messages],
                             ['textDocument/didChange', 'textDocument/didChange'])
            self.assertTrue(all(message['params']['uri'].endswith('/src/declarations.cj')
                                for message in rpc.messages))

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

    async def test_creation_and_deletion_send_lifecycle_notifications(self):
        # arrange
        rpc = RecordingLsp()
        before = {'src/main.cj': 'package audit\n', 'src/old.cj': 'package audit\n'}
        after = {'files': {'src/main.cj': before['src/main.cj'], 'src/new.cj': 'package audit\n'}}
        with tempfile.TemporaryDirectory() as folder:
            workspace = Path(folder)
            (workspace / 'src').mkdir()
            (workspace / 'src/old.cj').write_text(before['src/old.cj'])

            # act
            await apply_step(rpc, workspace, before, after, 2)

            # assert
            self.assertFalse((workspace / 'src/old.cj').exists())
            self.assertTrue((workspace / 'src/new.cj').exists())
            self.assertEqual([message['method'] for message in rpc.messages], [
                'textDocument/didClose', 'workspace/didChangeWatchedFiles',
                'workspace/didChangeWatchedFiles', 'textDocument/didOpen'])
            self.assertEqual([m['params']['changes'][0]['type'] for m in rpc.messages
                              if m['method'] == 'workspace/didChangeWatchedFiles'], [3, 1])
