"""Exercise composed semantic views through native Python bindings."""


class SemanticChecks:
    def _check_semantic_exports(self, root, run):
        # arrange
        path = root / 'src/semantic_api.cj'
        path.write_text(
            'package sample\n'
            'interface SemanticBase { func value(): Int64 }\n'
            'class SemanticChild <: SemanticBase {\n'
            '    public func value(): Int64 { 1 }\n'
            '}\n'
            'func semanticUse(): Int64 { identity(shared()) }\n'
            'func semanticMissing() { noSemanticTarget() }\n',
            encoding='utf-8', newline='\n',
        )
        try:
            self._check_semantic_discovery(run)
            self._check_semantic_project(run)
            self._check_semantic_scope(run)
            self._check_semantic_resolution(run)
            self._check_semantic_location(run)
            self._check_semantic_syntax(run)
            self._check_semantic_relationships(run)
            self._check_semantic_inference(run)
            self._check_semantic_staleness(path, run)
        finally:
            path.unlink()

    def _check_semantic_discovery(self, run):
        # act
        checked = run("""
            import sys, types
            a = workspace.analysis()
            s = a.semantic()

            # assert
            assert isinstance(s, SemanticAnalysis)
            assert 'db' not in dir(s)
            assert {'at', 'inFile', 'project', 'syntax', 'syntaxAt'} <= set(dir(SemanticAnalysis))
            assert {'bodyResolutions', 'calls', 'resolutions', 'usages', 'incomingCalls',
                    'outgoingCalls', 'directSupertypes', 'directSubtypes',
                    'directImplementations', 'directImplementers', 'contextualPackage',
                    'syntaxOrigins'} <= set(dir(SemanticObject))
            assert {'resolution', 'contextualFile'} <= set(dir(SemanticOccurrence))
            assert 'contextualFile' in dir(SemanticLocation)
            for cls in [SemanticAnalysis, SemanticObject, SemanticFile, SemanticSyntaxPointer]:
                try:
                    cls()
                except TypeError:
                    pass
                else:
                    raise AssertionError(f'snapshot objects must not be fabricated: {cls}')
            sys.modules['_semantic_exports_hold'] = types.SimpleNamespace(a=a, s=s)
            result = True
        """)

        # assert
        self.assertTrue(checked['result'])

    def _check_semantic_project(self, run):
        # act
        checked = run("""
            from _semantic_exports_hold import s
            import _semantic_exports_hold as held
            project = s.project()
            module = next(m for m in project.modules() if m.isWorkspaceMember())
            configuration = module.configuration()
            package = next(p for p in project.packages() if p.name() == 'sample')
            exports = package.exports()

            # assert
            assert isinstance(project, SemanticProject)
            assert isinstance(module.identity, Module)
            assert isinstance(module.root(), VfsPath)
            assert module.root().isUnder(VfsPath.file(workspace.root))
            assert VfsPath.file(workspace.root) == VfsPath.file(workspace.root)
            assert module.root().name
            assert isinstance(configuration, SemanticConfiguration)
            assert not configuration.hasCompleteCompilerInvocation
            assert configuration.loadingProblems is None
            assert module.inactiveFiles() == []
            assert all(isinstance(b, BinaryModel) for b in project.binaries())
            assert all(isinstance(d, SemanticDependency) for d in project.dependencies())
            assert package.origin() == SemanticPackageOrigin.WorkspacePackage()
            assert isinstance(exports, SemanticExports)
            assert any(b.name == 'identity' for b in exports.names)
            assert exports.isAvailable and not exports.isCyclic
            assert package.unavailableFiles() == []
            held.project, held.package = project, package
            result = True
        """)

        # assert
        self.assertTrue(checked['result'])

    def _check_semantic_scope(self, run):
        # act
        checked = run("""
            from _semantic_exports_hold import a, s
            import _semantic_exports_hold as held
            file_id = a.fileId('src/semantic_api.cj')
            text = a.text('src/semantic_api.cj')
            occurrence = s.at(file_id, text.encode().index(b'identity(shared())'))
            file = occurrence.contextualFile()
            lookup = file.lookup('identity', Namespace.Values())

            # assert
            assert isinstance(occurrence, SemanticOccurrence)
            assert 'analysis' not in dir(occurrence)
            assert isinstance(file, SemanticFile) and not file.isTest()
            assert file.imports() == []
            assert any(b.name == 'identity' for b in file.visibleNames())
            assert isinstance(lookup, Resolution)
            assert file.conditions() == []
            assert isinstance(file.whenStatus(), WhenDiagnostics)
            held.file_id, held.text = file_id, text
            held.occurrence, held.file = occurrence, file
            result = True
        """)

        # assert
        self.assertTrue(checked['result'])

    def _check_semantic_resolution(self, run):
        # act
        checked = run("""
            from _semantic_exports_hold import s, file_id, text, occurrence, package
            import _semantic_exports_hold as held
            resolution = occurrence.resolution()
            call = resolution.call
            missing = s.at(file_id, text.encode().index(b'noSemanticTarget')).resolution()
            bindings = call.bindings()
            target = call.callable()

            # assert
            assert resolution.status == SemanticResolutionStatus.ResolvedMeaning()
            assert isinstance(call, SemanticCallResolution)
            assert missing.status == SemanticResolutionStatus.UnresolvedMeaning()
            assert isinstance(missing.reason, SemanticResolutionReason)
            assert call.status == SemanticResolutionStatus.ResolvedMeaning()
            assert call.signature().display() == '(Int64) -> Int64'
            assert call.argumentParameters() == [0]
            assert not call.isSetter
            assert len(bindings) == 1
            assert isinstance(bindings[0], SemanticGenericBinding)
            assert bindings[0].valueType.display() == 'Int64'
            assert isinstance(bindings[0].valueType.kind(), SemanticTypeKind.PrimitiveType)
            assert target.contextualPackage().identity == package.identity
            assert isinstance(target.identity, SemanticIdentity.NamedIdentity)
            assert target.identity == target.identity
            assert call.callee.semanticType().display() == '(Int64) -> Int64'
            try:
                SemanticObject(s, target.identity)
            except TypeError:
                pass
            else:
                raise AssertionError('snapshot constructor was exported')
            held.target = target
            result = True
        """)

        # assert
        self.assertTrue(checked['result'])

    def _check_semantic_location(self, run):
        # act
        checked = run("""
            from _semantic_exports_hold import occurrence, text, file
            import _semantic_exports_hold as held
            location = occurrence.location

            # assert
            assert location.kind() == SemanticSourceKind.PhysicalSource()
            assert location.excerpt() == 'identity'
            assert location.sourceText() == text
            assert location.coordinates()[0] == 5
            assert location.contextualFile().identity == file.identity
            held.location = location
            result = True
        """)

        # assert
        self.assertTrue(checked['result'])

    def _check_semantic_syntax(self, run):
        # act
        checked = run("""
            from _semantic_exports_hold import a, s, file_id, text, target
            import _semantic_exports_hold as held
            tree = s.syntaxAt(file_id)
            syntax = tree.root()
            resolved = tree.resolve(syntax.pointer())
            origins = target.syntaxOrigins()
            foreign = a.semantic().syntaxAt(file_id)

            # assert
            assert isinstance(tree, SemanticSyntaxTree) and tree.errors() == []
            assert syntax.kindName() and syntax.text() == text
            assert resolved.text() == text
            try:
                foreign.resolve(syntax.pointer())
            except RuntimeError as error:
                assert 'another analysis' in str(error), str(error)
            else:
                raise AssertionError('foreign syntax pointer was accepted')
            assert any(e.isToken() for e in syntax.descendants())
            assert origins and isinstance(origins[0], SemanticSyntaxOrigin.SourceSyntax)
            declaration = origins[0].field0
            assert any(m.object.identity == target.identity for m in declaration.mappings())
            assert isinstance(target.origins()[0], SemanticOrigin.SourceOrigin)
            held.tree, held.syntax, held.pointer = tree, syntax, syntax.pointer()
            result = True
        """)

        # assert
        self.assertTrue(checked['result'])

    def _check_semantic_relationships(self, run):
        # act
        checked = run("""
            from _semantic_exports_hold import s, file_id, text, target, occurrence
            incoming = target.incomingCalls()
            child = s.at(file_id, text.encode().index(b'SemanticChild')).definitions[0]
            bases = child.directSupertypes()
            member = s.at(file_id, text.encode().rindex(b'value():')).definitions[0]
            implementations = member.directImplementations()

            # assert
            assert incoming and all(isinstance(e, SemanticCallEdge) for e in incoming)
            assert any(e.caller.identity == occurrence.owner.identity for e in incoming)
            assert isinstance(occurrence.owner.outgoingCalls(), SemanticCalls)
            assert isinstance(target.usages(), SemanticUsages)
            assert isinstance(occurrence.owner.bodyResolutions(), SemanticBodyResolutions)
            assert occurrence.owner.calls() and occurrence.owner.resolutions()
            assert len(bases) == 1 and isinstance(bases[0], SemanticHierarchyEdge)
            assert any(e.subtype.identity == child.identity
                       for e in bases[0].supertype.directSubtypes())
            assert len(implementations) == 1
            edge = implementations[0]
            assert isinstance(edge, SemanticImplementationEdge)
            assert edge.implementation.identity == member.identity
            assert any(e.implementation.identity == member.identity
                       for e in edge.declaration.directImplementers())
            result = True
        """)

        # assert
        self.assertTrue(checked['result'])

    def _check_semantic_inference(self, run):
        # act
        checked = run("""
            from _semantic_exports_hold import a
            owner = next(d for d in a.declarations('src/semantic_api.cj')
                         if 'semanticUse' in a.item(d).names)
            inferred = a.infer(owner)
            source_map = a.loweredBody(owner).sourceMap
            raw = next(c for c in inferred.calls if c.bindings)
            retained = inferred.callOf(raw.expr)

            # assert
            for i, origin in enumerate(source_map.exprs):
                if origin.written is not None:
                    assert ExprId(i) in source_map.exprsAtSource(origin.written)
                    assert any(source.range == origin.written.range
                               for source in source_map.sourcesOfExpr(ExprId(i)))
            assert isinstance(raw, CallResolution)
            assert raw.outcome == CallResolutionOutcome.Resolved()
            assert raw == retained
            assert isinstance(raw.bindings[0], GenericBinding)
            assert raw.bindings[0] == retained.bindings[0]
            assert a.typeText(raw.bindings[0].ty) == 'Int64'
            result = True
        """)

        # assert
        self.assertTrue(checked['result'])

    def _check_semantic_staleness(self, path, run):
        # act - keep native objects across calls, then invalidate their snapshot.
        path.write_text(f'{path.read_text()}// changed revision\n', encoding='utf-8')
        stale = run("""
            import sys
            held = sys.modules.pop('_semantic_exports_hold')
            operations = [held.project.modules, held.target.calls, held.location.sourceText,
                          held.syntax.children, held.file.visibleNames,
                          lambda: held.tree.resolve(held.pointer)]

            # assert
            for operation in operations:
                try:
                    operation()
                except RuntimeError:
                    pass
                else:
                    raise AssertionError('stale semantic view was accepted')
            fresh = workspace.analysis().semantic()
            assert fresh.project().modules()
            result = len(operations)
        """)

        # assert
        self.assertEqual(stale['result'], 6)
