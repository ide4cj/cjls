"""Root routing and session isolation through the real stdio connection."""

import subprocess


class WorktreeChecks:
    def _check_worktree_sessions(self, root, rpc, run):
        def git(*args):
            subprocess.run(["git", "-C", str(root), *args], check=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        git("init", "-q")
        git("add", "cjpm.toml", "src")
        git("-c", "user.name=MCP Test", "-c", "user.email=mcp@example.invalid",
            "-c", "core.hooksPath=/dev/null", "commit", "-qm", "fixture")
        other = root / ".codex/worktrees/other"
        git("worktree", "add", "--detach", str(other), "HEAD")
        (other / "src/helper.cj").write_text(
            "package sample\npublic func otherOnly(): Int64 { 7 }\n", encoding="utf-8")
        query = """
            a = workspace.analysis()
            result = {'root': workspace.root, 'load': workspace.loadDiagnostics,
                      'macros': workspace.macros,
                      'text': a.text('src/helper.cj'),
                      'names': [s.name for s in a.fileSymbols('src/helper.cj')]}
        """
        first = run(query)
        second = run(query, root=other)
        self.assertEqual(first['root'], str(root.resolve()))
        self.assertEqual(second['root'], str(other.resolve()))
        self.assertEqual(second['result']['root'], second['root'])
        self.assertNotEqual(first['sessionId'], second['sessionId'])
        self.assertIn('shared', first['result']['names'])
        self.assertNotIn('shared', second['result']['names'])
        self.assertIn('otherOnly', second['result']['names'])
        self.assertEqual(first, run(query))  # Omission selects --dir, never the last call.
        alias = root / 'other-alias'
        alias.symlink_to(other, target_is_directory=True)
        self.assertEqual(second, run(query, root=alias / 'src/..'))

        # Recovery belongs to the selected root even after several runner initializations.
        run("result = 'A' * 25000", error=True)
        self.assertIsNone(run("result = last_output", root=other)['result'])
        run("result = 'B' * 25000", root=other, error=True)
        self.assertEqual(run("result = last_output['result'][:1]")['result'], 'A')
        self.assertEqual(run("result = last_output['result'][:1]", root=other)['result'], 'B')
        self.assertEqual(run("result = last_output['sessionId']", root=other)['result'], second['sessionId'])

        # A checked edit affects only the selected root and a later revision there.
        edited = run("""
            a = workspace.analysis()
            before = a.text('src/helper.cj')
            span = TextRange(0, len(before.encode()))
            report = workspace.applyChange(SourceChange([FileChange.EditFile(
                'src/helper.cj', before, [TextEdit(span,
                'package sample\\npublic func changedOnly(): Int64 { 9 }\\n')])]), a.revision)
            result = report.isSuccess
        """, root=other)
        self.assertTrue(edited['result'])
        changed = run(query, root=other)
        self.assertGreater(changed['revision'], second['revision'])
        self.assertEqual(changed['sessionId'], second['sessionId'])
        self.assertIn('changedOnly', changed['result']['names'])
        self.assertEqual(first, run(query))
        self.assertEqual(run("result = workspace.diagnostics('src/helper.cj')", root=other)['result'], [])

        missing = root / 'does-not-exist'
        for bad in [missing, root / 'cjpm.toml']:
            response = rpc('tools/call', {'name': 'runPython', 'arguments':
                           {'root': str(bad), 'code': "from pathlib import Path; Path(workspace.root, 'wrong-root').touch()"}})
            self.assertTrue(response['isError'], response)
            self.assertIsNone(response['structuredContent']['revision'])
            self.assertIsNone(response['structuredContent']['sessionId'])
        self.assertFalse((root / 'wrong-root').exists())
        self.assertEqual(first, run(query))

        run("import sys, types; sys.modules['_worktree_hold'] = types.SimpleNamespace(a=workspace.analysis())", root=other)
        run(query)  # Keep the default root newer than the held worktree.
        # The fifth distinct root evicts the least recently used entry, not the newest.
        for i in range(3):
            extra = root / '.codex/worktrees' / f'extra{i}'
            extra.mkdir(parents=True)
            (extra / 'cjpm.toml').write_text((root / 'cjpm.toml').read_text())
            (extra / 'src').mkdir()
            (extra / 'src/main.cj').write_text('package sample\nmain() {}\n')
            run('result = workspace.root', root=extra)
        self.assertEqual(first, run(query))
        reopened = run(query, root=other)
        self.assertNotEqual(reopened['sessionId'], second['sessionId'])
        run("""
            import sys
            try:
                sys.modules['_worktree_hold'].a.text('src/helper.cj')
            except RuntimeError as error:
                assert 'ContentModified' in str(error), error
            else:
                raise AssertionError('evicted analysis must be invalidated')
            del sys.modules['_worktree_hold']
        """, root=other)
        self.assertIsNone(run('result = last_output', root=other)['result'])

        # Observed deletion retires a session; reusing its pathname gets fresh state.
        git('worktree', 'remove', '--force', str(other))
        response = rpc('tools/call', {'name': 'runPython', 'arguments':
                       {'root': str(other), 'code': "raise AssertionError('must not run')"}})
        self.assertTrue(response['isError'])
        git('worktree', 'add', '--detach', str(other), 'HEAD')
        recreated = run(query, root=other)
        self.assertNotEqual(recreated['sessionId'], reopened['sessionId'])
        self.assertIn('shared', recreated['result']['names'])
        self.assertIsNone(run('result = last_output', root=other)['result'])

        # Same macro package/name in two worktrees must use independent build outputs.
        def macro_fixture(directory, value):
            macro_dir = directory / 'src/ms'
            macro_dir.mkdir(exist_ok=True)
            (macro_dir / 'macros.cj').write_text(
                'macro package sample.ms\nimport std.ast.*\n'
                'public macro Emit(input: Tokens): Tokens { '
                f'quote(public func rootValue(): Int64 {{ {value} }}) }}\n', encoding='utf-8')
            (directory / 'src/macro_use.cj').write_text(
                'package sample\nimport sample.ms.*\n@Emit public func placeholder(): Int64 { 0 }\n',
                encoding='utf-8')

        expansion_query = """
            a = workspace.analysis()
            assert workspace.loadDiagnostics == [], workspace.loadDiagnostics
            assert workspace.macros.state == MacroState.Settled(), workspace.macros
            assert workspace.macros.diagnostics == [], [d.message for d in workspace.macros.diagnostics]
            text = a.text('src/macro_use.cj')
            call = a.macroCall('src/macro_use.cj', text.encode().index(b'@Emit'))
            result = a.expansion(call.call).text
        """
        macro_fixture(root, 111)
        macro_fixture(other, 222)
        default_macro = run(expansion_query)
        other_macro = run(expansion_query, root=other)
        self.assertIn('111', default_macro['result'])
        self.assertIn('222', other_macro['result'])
        macro_fixture(other, 333)
        self.assertIn('333', run(expansion_query, root=other)['result'])
        self.assertEqual(default_macro, run(expansion_query))
