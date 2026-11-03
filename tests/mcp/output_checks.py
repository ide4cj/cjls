"""Output and source-presentation checks using the real server fixture."""

import json


class OutputChecks:
    def _check_output_budgets(self, root, run):
        # An oversized response after effects must be recoverable without replaying them.
        rejected = run("""
            from pathlib import Path
            Path(workspace.root, 'executed-once').write_text('done')
            result = 'я' * 13000
        """, error=True)
        self.assertIn('OutputBudgetExceeded', rejected['error'])
        self.assertEqual(rejected['outputBudget']['limit_bytes'], 24000)
        self.assertGreater(rejected['outputBudget']['actual_bytes'], 26000)
        self.assertEqual(rejected['stdout'], '')
        self.assertIsNone(rejected['result'])
        self.assertEqual((root / 'executed-once').read_text(), 'done')
        recovered = run("""
            assert last_output['revision'] == workspace.revision
            result = {'length': len(last_output['result']), 'first': last_output['result'][:1]}
        """)
        self.assertEqual(recovered['result'], {'length': 13000, 'first': 'я'})
        complete = run("result = last_output", max_output_bytes=0)
        self.assertEqual(complete['result']['result'], 'я' * 13000)
        large = run("result = 'x' * 25000", max_output_bytes=30000)
        self.assertEqual(len(large['result']), 25000)

        # All channels share one budget, including native fd output and tracebacks.
        for code, channel in [
            ("print('x' * 25000)", 'stdout'),
            ("import os; os.write(2, b'y' * 25000)", 'stderr'),
            ("raise ValueError('z' * 25000)", 'error'),
        ]:
            response = run(code, error=True)
            self.assertIn('OutputBudgetExceeded', response['error'])
            saved = run(f"result = len(last_output[{channel!r}])")
            self.assertGreater(saved['result'], 24000)
        exact = run("result = 'привет'")
        size = len(json.dumps(exact, ensure_ascii=False, separators=(',', ':')).encode())
        self.assertEqual(run("result = 'привет'", max_output_bytes=size), exact)
        self.assertIn('OutputBudgetExceeded',
                      run("result = 'привет'", max_output_bytes=size-1, error=True)['error'])
        # A tiny requested budget still returns an actionable error, not a truncated envelope.
        self.assertIn('last_output', run("result = 1", max_output_bytes=1, error=True)['error'])
        self.assertTrue(run("result = True")['result'])

    def _check_source_excerpts(self, run):
        checked = run("""
            import json
            a = workspace.analysis()
            path = 'src/main.cj'
            text = a.text(path).encode('utf-8')
            found = next(s for s in a.symbols('answer', 20) if s.symbol.name == 'answer')
            span = found.symbol.range
            page = source_excerpts(a, [(path, span)], context_lines=1)
            entry = page['excerpts'][0]
            assert entry['range'] == {'start': span.start, 'end': span.end}
            assert entry['source'].encode() == text[entry['shown_range']['start']:entry['shown_range']['end']]
            assert entry['start_line'] == max(1, text[:span.start].count(b'\\n')) and '// привет' in entry['source'], entry
            assert entry['end_line'] == 4, entry
            assert page['total'] == page['returned'] == 1 and page['omitted'] == 0
            assert page['revision'] == a.revision and page['next_offset'] is None
            # Exact semantic range, without context, is unchanged and UTF-8 safe.
            exact = source_excerpts(a, [(path, span)])
            assert exact['excerpts'][0]['source'] == text[span.start:span.end].decode()
            # Overloads remain separate requests, in original order.
            requests = [('src/helper.cj', s.range) for s in a.fileSymbols('src/helper.cj') if s.name == 'shared']
            assert len(requests) == 2
            first = source_excerpts(a, requests, limit=1)
            assert (first['total'], first['returned'], first['omitted'], first['next_offset']) == (2, 1, 1, 1)
            second = source_excerpts(a, requests, offset=first['next_offset'])
            assert second['excerpts'][0]['index'] == 1 and second['next_offset'] is None
            assert 'value: Int64' in second['excerpts'][0]['source']
            # Aggregate budget includes escaped JSON and metadata, not just source bytes.
            all_entries = source_excerpts(a, requests)
            full_size = len(json.dumps(all_entries, ensure_ascii=False, separators=(',', ':')).encode())
            small = source_excerpts(a, requests, max_bytes=full_size-1)
            assert len(json.dumps(small, ensure_ascii=False, separators=(',', ':')).encode()) <= full_size-1
            assert small['omitted'] > 0 and small['required_bytes'] >= full_size
            blocked = source_excerpts(a, [(path, TextRange(0, len(text)))], max_bytes=256)
            assert blocked['returned'] == 0 and blocked['next_offset'] == 0
            assert blocked['required_bytes'] > 256
            assert source_excerpts(a, [], max_bytes=256)['next_offset'] is None
            eof = source_excerpts(a, [(path, TextRange(len(text), len(text)))])
            assert eof['excerpts'][0]['source'] == ''
            bad = text.index('п'.encode()) + 1
            for span in [TextRange(bad, bad), TextRange(0, bad), TextRange(0, len(text)+1)]:
                try:
                    source_excerpts(a, [(path, span)])
                except (ValueError, UnicodeDecodeError):
                    pass
                else:
                    raise AssertionError('invalid UTF-8 range accepted')
            for kwargs in [dict(offset=-1), dict(offset=4), dict(limit=0),
                           dict(context_lines=-1), dict(max_bytes=255), dict(max_bytes=True)]:
                try:
                    source_excerpts(a, requests, **kwargs)
                except ValueError:
                    pass
                else:
                    raise AssertionError('invalid page option accepted')
            result = True
        """)
        self.assertTrue(checked['result'])


    def _check_large_source_workflow(self, run):
        # Like #49 calls 2-4: several large files, repeated reads, and test-suite prefixes.
        # Put targets after long unrelated declarations so a prefix is insufficient.
        run("""
            from pathlib import Path
            for i in range(6):
                filler = ''.join(f'func unrelated{i}_{j}(): Int64 {{ {j} }}\\n' for j in range(250))
                Path(workspace.root, f'src/large{i}.cj').write_text(
                    'package sample\\n// данные\\n' + filler +
                    f'func selected{i}(): Int64 {{ 17 }}\\n')
            result = True
        """)
        full = run("""
            a = workspace.analysis()
            result = [{'path': f'src/large{i}.cj', 'source': a.text(f'src/large{i}.cj')}
                      for i in range(6)]
        """, error=True)
        self.assertGreater(full['outputBudget']['actual_bytes'], 50000)
        small = run("""
            a = workspace.analysis()
            requests = []
            for i in range(6):
                path = f'src/large{i}.cj'
                node = next(s for s in a.fileSymbols(path) if s.name == f'selected{i}')
                requests.append((path, node.range))
            result = source_excerpts(a, requests, max_bytes=4000)
        """)
        page = small['result']
        self.assertEqual((page['total'], page['returned'], page['omitted']), (6, 6, 0))
        self.assertIsNone(page['next_offset'])
        self.assertTrue(all(f'selected{i}' in entry['source'] for i, entry in enumerate(page['excerpts'])))
        self.assertLess(len(json.dumps(small, ensure_ascii=False).encode()), 4000)
        edit = run("""
            import difflib
            a = workspace.analysis()
            path = 'src/large0.cj'
            node = next(s for s in a.fileSymbols(path) if s.name == 'selected0')
            before = a.text(path)
            data = before.encode()
            start = data.index(b'17', node.selectionRange.end, node.range.end)
            after = (data[:start] + b'18' + data[start+2:]).decode()
            # Both revision and expected-text checks remain mandatory.
            mismatch = workspace.applyChange(SourceChange([
                FileChange.EditFile(path, before + 'stale', [TextEdit(TextRange(start, start+2), '18')])
            ]), a.revision)
            assert not mismatch.isSuccess and mismatch.applied == []
            try:
                workspace.applyChange(SourceChange([]), a.revision - 1)
            except RuntimeError as error:
                assert 'ContentModified' in str(error)
            else:
                raise AssertionError('stale revision accepted')
            report = workspace.applyChange(SourceChange([
                FileChange.EditFile(path, before, [TextEdit(TextRange(start, start+2), '18')])
            ]), a.revision)
            assert report.isSuccess
            result = {'applied': report.applied, 'diff': list(difflib.unified_diff(
                before.splitlines(), after.splitlines(), n=2, lineterm=''))}
        """)
        self.assertEqual(edit['result']['applied'], [0])
        self.assertLess(len(json.dumps(edit).encode()), 1000)
        self.assertIn('+func selected0(): Int64 { 18 }', edit['result']['diff'])
        checked = run("""
            from pathlib import Path
            a = workspace.analysis()
            assert 'selected0(): Int64 { 18 }' in a.text('src/large0.cj')
            assert workspace.diagnostics('src/large0.cj') == []
            for i in range(6):
                Path(workspace.root, f'src/large{i}.cj').unlink()
            result = True
        """)
        self.assertGreater(checked['revision'], edit['revision'])

