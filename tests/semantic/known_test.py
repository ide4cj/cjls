"""Known differences follow annotated sources without weakening diagnostic checks."""

import unittest

from oracle import check_known, desired
from oracle_test import failure
from scenarios import parse_scenario


HEADER = """\
// ISSUE: 528
// PACKAGE: audit .
// STEP: initial
// CJC: audit clean
// SOURCE: src/main.cj annotated.cj
"""
PLAIN = 'package audit\nfunc f(): Int64 { 1 }\n'
ANNOTATED = PLAIN + '//                ^ d error: problem\n//              ^^^^^ extra error: extra\n'
SOURCES = {'annotated.cj': ANNOTATED, 'plain.cj': PLAIN}


class KnownTest(unittest.TestCase):
    def test_replacement_deletion_and_restore_follow_the_source(self):
        # arrange
        text = HEADER + '// KNOWN-MISSING: d issue=529\n// KNOWN-EXTRA: extra issue=544\n'
        text += '// STEP: fixed\n// CJC: audit clean\n// SOURCE: src/main.cj plain.cj\n'
        text += '// STEP: restored FROM initial\n'
        text += '// STEP: deleted\n// CJC: audit clean\n// DELETE-FILE: src/main.cj\n'
        text += '// SOURCE: src/other.cj plain.cj\n'

        # act
        case = parse_scenario(text, 'known', SOURCES.__getitem__)

        # assert
        initial, fixed, restored, deleted = case['steps']
        self.assertEqual(initial['known'], restored['known'])
        self.assertEqual(fixed['known'], {'missing': [], 'extra': []})
        self.assertEqual(deleted['known'], {'missing': [], 'extra': []})
        self.assertEqual(initial['files'], fixed['files'])
        self.assertEqual(fixed['changes'], {})
        self.assertEqual([d['id'] for d in initial['expected']], ['d'])
        self.assertEqual(initial['known']['extra'][0]['range'], [1, 16, 1, 21])

    def test_invalid_references_issues_and_conflicting_classifications_fail(self):
        # arrange
        examples = ('KNOWN-MISSING: absent issue=528', 'KNOWN-MISSING: d issue=0',
                    'KNOWN-EXTRA: absent issue=528', 'KNOWN-EXTRA: extra',
                    'KNOWN-MISSING: d issue=528\n// KNOWN-MISSING: d issue=529',
                    'KNOWN-MISSING: d issue=528\n// KNOWN-EXTRA: d issue=529')
        for directives in examples:
            with self.subTest(directives=directives):
                text = HEADER + '// ' + directives + '\n'

                # act
                error = failure(lambda: parse_scenario(text, 'invalid', SOURCES.__getitem__))

                # assert
                self.assertIsInstance(error, ValueError)

    def test_two_identical_extra_annotations_preserve_multiplicity(self):
        # arrange
        sources = {'annotated.cj': PLAIN + '//                ^ a error: extra\n'
                                       + '//                ^ b error: extra\n'}
        text = HEADER + '// KNOWN-EXTRA: a issue=544\n// KNOWN-EXTRA: b issue=544\n'
        case = parse_scenario(text, 'duplicates', sources.__getitem__)
        step = case['steps'][0]
        extra = {key: value for key, value in step['known']['extra'][0].items() if key != 'issue'}

        # act
        delta = check_known(case, step, [extra, extra])
        error = failure(lambda: check_known(case, step, [extra]))

        # assert
        self.assertEqual(desired(step), [])
        self.assertEqual(len(delta['extra']), 2)
        self.assertIsInstance(error, AssertionError)
