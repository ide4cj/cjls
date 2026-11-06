"""The committed runtime SDK window must follow both pin files."""

import unittest

import sdk_window_codegen as codegen


class SdkWindowCodegenTest(unittest.TestCase):
    def test_generated_window_matches_release_and_nightly_pins(self):
        # arrange
        committed = (codegen.ROOT / codegen.OUTPUT).read_text()

        # act
        generated = codegen.generate()

        # assert
        self.assertEqual(committed, generated)
