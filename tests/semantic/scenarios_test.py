"""Scenario parsing, coordinate mapping and document lifecycle regressions."""

import argparse
import contextlib
import io
from pathlib import Path
import tempfile
import textwrap
import unittest

from oracle import apply_step, prepare_workspace, read_json, run, validate
from scenarios import load_scenarios, parse_scenario as parse_descriptor, relative_path, source_annotations


SIMPLE = """\
// ISSUE: 528
// PACKAGE: audit .
// STEP: initial
// CJC: audit clean
// SOURCE: src/main.cj main.cj
"""
SOURCES = {
    'main.cj': 'package audit\nfunc f(): Int64 { 1 }\n',
    'marked.cj': 'package audit\nfunc f(): Int64 { 1 }\n//                ^ result warning: example\n',
    'other.cj': 'package audit\nlet value = 1\n//          ^ other warning: example\n',
}


def parse_scenario(text, ident):
    return parse_descriptor(text, ident, SOURCES.__getitem__)


class ScenarioTest(unittest.TestCase):
    def test_carets_map_scalar_columns_to_utf16_multiline_points_and_overlaps(self):
        # arrange
        text = ('let x = "😀"; ab\n'
                '//           ^^^^ outer error: outer\n'
                '//            ^^^^ inner warning: inner\n'
                'cd\n'
                '//| point error: point\n')

        # act
        source, diagnostics = source_annotations(text)

        # assert
        self.assertEqual(source, 'let x = "😀"; ab\ncd\n')
        self.assertEqual(diagnostics, [
            {'id': 'outer', 'range': [0, 14, 1, 1], 'severity': 1, 'message': 'outer'},
            {'id': 'inner', 'range': [0, 15, 1, 2], 'severity': 2, 'message': 'inner'},
            {'id': 'point', 'range': [1, 2, 1, 2], 'severity': 1, 'message': 'point'},
        ])

    def test_invalid_or_detached_annotations_fail(self):
        # arrange
        examples = ('//^ d error: no source\n',
                    'let x = 1\n//     ^ missing message\n',
                    'let x = 1\n//                       ^ d error: outside source\n',
                    '  a\n//^ d error: first\n//^ d error: duplicate\n')
        for text in examples:
            with self.subTest(text=text):
                # act / assert
                with self.assertRaises(ValueError):
                    source_annotations(text)

    def test_common_margin_allows_annotations_at_the_first_column(self):
        # arrange
        text = '  package audit\n  let value = 1\n//^^^ binding error: example\n'

        # act
        source, diagnostics = source_annotations(text)

        # assert
        self.assertEqual(source, 'package audit\nlet value = 1\n')
        self.assertEqual(diagnostics[0]['range'], [1, 0, 1, 3])

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
            SIMPLE + '//^ d error: misplaced annotation\n',
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

    def test_stale_baseline_steps_and_diagnostic_ids_fail(self):
        # arrange
        case = parse_scenario(SIMPLE, 'example')
        entry = {'issue': 528, 'steps': ['initial'], 'missing': [], 'extra': [
            {'file': 'src/main.cj', 'range': [0, 0, 0, 0], 'severity': 1, 'message': 'example'}]}
        for field, value in [('missing', ['absent']), ('steps', ['absent'])]:
            with self.subTest(field=field):
                baseline = {'example': {**entry, field: value}}

                # act / assert
                with self.assertRaisesRegex(ValueError, 'orphan baseline'):
                    validate([case], baseline)

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
