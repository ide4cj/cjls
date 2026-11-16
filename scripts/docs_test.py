"""Tests of scripts/docs.py: python3 -m unittest discover -s scripts -p '*_test.py'"""

import shutil
import tempfile
import unittest
from pathlib import Path

import docs
from docs import Adr, DocsError


def adr_dir(files):
    directory = Path(tempfile.mkdtemp())
    for name, text in files.items():
        (directory / name).write_text(text, encoding="utf-8")
    return directory


ONE = "# ADR-0001: Files are ropes\n\nStatus: accepted, 2026-09-01\n\n## Context\n"
TWO = ("# ADR-0002: Ropes are stamped\n\nStatus: accepted, 2026-09-02\n"
       "Amends ADR-0001: stamps\n\n## Context\n\nAmends ADR-0001: not in the header\n")


class ReadAdrsTest(unittest.TestCase):
    def test_a_header_gives_the_number_the_decision_the_status_and_what_it_amends(self):
        # arrange
        directory = adr_dir({"0001-ropes.md": ONE, "0002-stamps.md": TWO, "README.md": "x"})

        # act
        adrs = docs.read_adrs(directory)

        # assert
        self.assertEqual(adrs, [
            Adr(1, "0001-ropes.md", "Files are ropes", "accepted", []),
            Adr(2, "0002-stamps.md", "Ropes are stamped", "accepted", [(1, "stamps")]),
        ])

    def test_a_superseded_adr_is_shown_by_the_d_of_the_one_replacing_it(self):
        # arrange
        old = ONE.replace("accepted, 2026-09-01", "superseded by ADR-0002, 2026-09-02")
        directory = adr_dir({"0001-ropes.md": old, "0002-stamps.md": TWO.replace("Amends", "x")})

        # act
        adrs = docs.read_adrs(directory)

        # assert
        self.assertEqual(adrs[0].status, "superseded by D2")

    def test_two_files_of_one_number_are_an_error_naming_both(self):
        # arrange
        directory = adr_dir({"0001-ropes.md": ONE, "0001-trees.md": ONE})

        # act
        with self.assertRaises(DocsError) as raised:
            docs.read_adrs(directory)

        # assert
        self.assertRegex(str(raised.exception), "ADR-0001 twice: 0001-ropes.md and 0001-trees.md")

    def test_a_header_whose_number_is_not_its_files_is_an_error(self):
        # arrange
        directory = adr_dir({"0003-ropes.md": ONE})

        # act
        with self.assertRaises(DocsError) as raised:
            docs.read_adrs(directory)

        # assert
        self.assertRegex(str(raised.exception), "its header says ADR-0001")

    def test_a_header_without_a_status_is_an_error(self):
        # arrange
        directory = adr_dir({"0001-ropes.md": "# ADR-0001: Files are ropes\n\n## Context\n"})

        # act
        with self.assertRaises(DocsError) as raised:
            docs.read_adrs(directory)

        # assert
        self.assertRegex(str(raised.exception), "no `Status")

    def test_amending_an_adr_that_is_not_there_is_an_error(self):
        # arrange
        directory = adr_dir({"0002-stamps.md": TWO})

        # act
        with self.assertRaises(DocsError) as raised:
            docs.read_adrs(directory)

        # assert
        self.assertRegex(str(raised.exception), "names ADR-0001, which is not another ADR")


class IndexTest(unittest.TestCase):
    def test_an_amended_adr_shows_the_amending_ones_in_its_row_by_number(self):
        # arrange
        adrs = [
            Adr(1, "0001-a.md", "A", "accepted", []),
            Adr(2, "0002-b.md", "B", "accepted", [(1, "stamps")]),
            Adr(3, "0003-c.md", "C", "accepted", [(1, "a re-export is its package's, not its file's")]),
        ]

        # act
        rows = docs.index_rows(adrs)

        # assert
        self.assertEqual(rows[0], "| [0001](0001-a.md) | A | accepted; stamps by D2; "
                                  "a re-export is its package's, not its file's, by D3 |")
        self.assertEqual(rows[1], "| [0002](0002-b.md) | B | accepted |")

    def test_the_table_is_replaced_and_what_is_around_it_kept(self):
        # arrange
        text = f"# ADR\n\nintro\n\n{docs.TABLE_HEAD}\n{docs.TABLE_RULE}\n| old | row | x |\n\nafter\n"

        # act
        once = docs.write_index(text, ["| new | row | y |"])

        # assert
        self.assertEqual(once, f"# ADR\n\nintro\n\n{docs.GENERATED}\n\n{docs.TABLE_HEAD}\n"
                               f"{docs.TABLE_RULE}\n| new | row | y |\n\nafter\n")

        # act
        twice = docs.write_index(once, ["| new | row | y |"])

        # assert
        self.assertEqual(twice, once)


class RulesTest(unittest.TestCase):
    def test_a_rule_id_twice_in_its_file_is_an_error_struck_through_or_not(self):
        # arrange
        root = Path(tempfile.mkdtemp())
        for prefix, name in docs.RULES.items():
            (root / name).parent.mkdir(parents=True, exist_ok=True)
            (root / name).write_text(f"| {prefix}1 | a |\n| ~~{prefix}2~~ | b |\n", encoding="utf-8")
        (root / docs.RULES["A"]).write_text("| A1 | a |\n| ~~A1~~ | b |\n| S1 | not A's |\n")

        # act
        with self.assertRaises(DocsError) as raised:
            docs.check_rules(root)

        # assert
        self.assertRegex(str(raised.exception), "02-analysis.md: A1 twice")

    def test_the_rules_of_this_repository_have_each_id_once(self):
        # arrange
        root = docs.ROOT

        # act
        result = docs.check_rules(root)

        # assert
        self.assertIsNone(result)


class LinksTest(unittest.TestCase):
    def test_removed_heading_is_rejected_with_source_and_line(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'AGENTS.md').write_text('# Before changing code\n')
            source = root / 'README.md'
            source.write_text('[rules](AGENTS.md#efficient-cjmcp-queries)\n')
            with self.assertRaisesRegex(DocsError, 'README.md:1:.*missing heading'):
                docs.check_links(root)
            source.write_text('[rules](AGENTS.md#before-changing-code)\n')
            docs.check_links(root)

    def test_headings_duplicates_escapes_and_fenced_examples(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            text = ('# `API`: Café &amp; tests\n## Again\n## Again\n'
                    '<a id="explicit"></a>\n'
                    '[one](#api-café--tests) [two](#again-1) [three](#explicit)\n'
                    '[encoded](#api-caf%C3%A9--tests)\n'
                    '[remote](https://example.com/missing#heading)\n'
                    '```markdown\n[example](absent.md)\n# Fake\n```\n'
                    '`[inline](absent.md)`\n')
            (root / 'README.md').write_text(text, encoding='utf-8')
            docs.check_links(root)
            self.assertNotIn('fake', docs.markdown_anchors(text))

    def test_missing_file_and_escaping_skill_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'README.md').write_text('[missing](absent.md)\n')
            with self.assertRaisesRegex(DocsError, 'missing local destination'):
                docs.check_links(root)
            (root / 'README.md').write_text('[outside](../README.md)\n')
            with self.assertRaisesRegex(DocsError, 'escapes the installed skill'):
                docs.check_links(root, contained=True)

    def test_reference_destinations_and_angle_paths_are_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'API guide.md').write_text('# API\n')
            source = root / 'README.md'
            source.write_text('[api]: <API guide.md#api>\n[guide](<API guide.md#api>)\n')
            docs.check_links(root)
            source.write_text('[api]: <API guide.md#removed>\n')
            with self.assertRaisesRegex(DocsError, 'missing heading'):
                docs.check_links(root)

    def test_skill_links_survive_copying_only_the_skill(self):
        with tempfile.TemporaryDirectory() as directory:
            copied = Path(directory) / 'cangjie-mcp'
            shutil.copytree(docs.ROOT / 'modules/cjmcp/skills/cangjie-mcp', copied)
            docs.check_links(copied, list(copied.rglob('*.md')), contained=True)


class OpenPrsTest(unittest.TestCase):
    MINE = {171: [(56, "0056-mine.md")]}

    def test_an_older_pull_request_with_the_number_fails_the_younger(self):
        # arrange
        number = 171

        # act
        with self.assertRaises(DocsError) as raised:
            docs.check_open_prs(number, {170: [(56, "0056-theirs.md")], **self.MINE})

        # assert
        self.assertRegex(str(raised.exception), r"ADR-0056 is #170's \(0056-theirs.md\)")

    def test_a_younger_pull_request_with_the_number_is_its_own_concern(self):
        # arrange
        number = 170

        # act
        result = docs.check_open_prs(number, {170: [(56, "0056-theirs.md")], **self.MINE})

        # assert
        self.assertIsNone(result)

    def test_a_pull_request_stacked_on_an_older_one_adding_its_adr_is_no_clash(self):
        # arrange
        number = 171

        # act
        result = docs.check_open_prs(number, {170: [(56, "0056-mine.md")], **self.MINE})

        # assert
        self.assertIsNone(result)

    def test_an_older_pull_request_adding_a_number_master_took_fails_only_itself(self):
        # master has 0056 as well: #170 is to move, #171 adds another number
        # arrange
        number = 171

        # act
        result = docs.check_open_prs(number, {170: [(56, "0056-theirs.md")], 171: [(57, "0057-mine.md")]})

        # assert
        self.assertIsNone(result)

    def test_a_pull_request_adding_no_adr_clashes_with_none(self):
        # arrange
        number = 171

        # act
        result = docs.check_open_prs(number, {170: [(56, "0056-theirs.md")]})

        # assert
        self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()
