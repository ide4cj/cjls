"""Structured status/diagnostic serialization through the real MCP transport."""

class DiagnosticChecks:
    def _check_structured_diagnostics(self, run):
        # arrange
        script = """
            assert not hasattr(workspace, 'problems')
            assert not hasattr(workspace, 'hasExpandedMacros')
            assert isinstance(workspace.macros, MacroStatus)
            assert isinstance(workspace.macros.state, MacroState.Settled)
            assert workspace.macros.state == MacroState.Settled()
            assert MacroState.Pending() == MacroState.Pending()
            assert MacroState.Pending() != MacroState.Settled()
            assert MacroState.Settled() == MacroState.Settled()
            import sys
            if sys.version_info >= (3, 10):
                exec('match workspace.macros.state:\\n'
                     '    case MacroState.Settled(): pass\\n'
                     '    case _: raise AssertionError("expected settled macro state")')
            assert workspace.loadDiagnostics == []
            warning = WorkspaceDiagnostic('macro', Severity.Warning(), 'review: привет',
                code='macro_expansion', path='/source.cj', range=TextRange(4, 10),
                line=2, column=3)
            hint = WorkspaceDiagnostic('analysis', Severity.Hint(), 'inactive',
                unnecessary=True)
            result = {'pending': MacroStatus(MacroState.Pending(), [warning]),
                      'settled': MacroStatus(MacroState.Settled(), [hint]),
                      'states': [MacroState.Pending(), MacroState.Settled()],
                      'range': TextRange(0, 0), 'severity': Severity.Error()}
        """

        # act
        encoded = run(script)

        # assert
        values = encoded['result']
        self.assertEqual(values['pending']['state'], 'pending')
        warning = values['pending']['diagnostics'][0]
        self.assertEqual(warning['severity'], 'warning')
        self.assertEqual(warning['code'], 'macro_expansion')
        self.assertEqual(warning['message'], 'review: привет')
        self.assertEqual(warning['range'], {'start': 4, 'end': 10})
        self.assertEqual((warning['path'], warning['line'], warning['column']),
                         ('/source.cj', 2, 3))
        hint = values['settled']['diagnostics'][0]
        self.assertEqual(hint['severity'], 'hint')
        self.assertTrue(hint['unnecessary'])
        for field in ('code', 'path', 'range', 'line', 'column'):
            self.assertIsNone(hint[field], hint)
        self.assertEqual(values['range'], {'start': 0, 'end': 0})
        self.assertEqual(values['severity'], 'error')
        self.assertEqual(values['states'], ['pending', 'settled'])

        # act - strings must not bypass the native enum contract.
        invalid = run("result = MacroStatus('pending', [])", error=True)

        # assert
        self.assertIn('TypeError', invalid['error'])
        self.assertEqual(run('result = workspace.macros.state')['result'], 'settled')

        # Native conversion must precede budget checking and retain plain JSON for recovery.
        rejected = run("""
            result = MacroStatus(MacroState.Settled(), [
                WorkspaceDiagnostic('macro', Severity.Error(), 'я' * 13000,
                                    code='macro_build')])
        """, error=True)
        self.assertIn('OutputBudgetExceeded', rejected['error'])
        self.assertGreater(rejected['outputBudget']['actual_bytes'], 26000)
        recovered = run("""
            assert isinstance(last_output['result'], dict)
            diagnostic = last_output['result']['diagnostics'][0]
            result = {'state': last_output['result']['state'],
                      'code': diagnostic['code'], 'severity': diagnostic['severity'],
                      'length': len(diagnostic['message']), 'path': diagnostic['path'],
                      'revision': last_output['revision']}
        """)
        self.assertEqual(recovered['result'], {'state': 'settled', 'code': 'macro_build',
            'severity': 'error', 'length': 13000, 'path': None,
            'revision': rejected['revision']})
        complete = run('result = last_output', max_output_bytes=0)
        self.assertEqual(complete['result']['result']['diagnostics'][0]['message'], 'я' * 13000)

        # The finite encoder must still reject unrelated non-serializable values.
        failure = run("result = object()", error=True)
        self.assertIn('not JSON serializable', failure['error'])
        self.assertTrue(run('result = True')['result'])
