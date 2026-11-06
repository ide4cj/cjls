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

        # act - compose project, scope, resolution, type, syntax and reverse relationships.
        checked = run("""
            import sys, types
            a = workspace.analysis()
            s = a.semantic()
            assert isinstance(s, SemanticAnalysis)
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
                    raise AssertionError('snapshot objects must not be fabricated: ' + str(cls))
            project = s.project()
            assert isinstance(project, SemanticProject)
            module = next(m for m in project.modules() if m.isWorkspaceMember())
            assert isinstance(module.identity, Module)
            assert isinstance(module.root(), VfsPath)
            assert module.root().isUnder(VfsPath.file(workspace.root))
            assert VfsPath.file(workspace.root) == VfsPath.file(workspace.root)
            assert module.root().name
            assert isinstance(module.configuration(), SemanticConfiguration)
            assert not module.configuration().hasCompleteCompilerInvocation
            assert module.configuration().loadingProblems is None
            assert module.inactiveFiles() == []
            assert all(isinstance(b, BinaryModel) for b in project.binaries())
            assert all(isinstance(d, SemanticDependency) for d in project.dependencies())
            package = next(p for p in project.packages() if p.name() == 'sample')
            assert package.origin() == SemanticPackageOrigin.WorkspacePackage()
            assert isinstance(package.exports(), SemanticExports)
            assert any(b.name == 'identity' for b in package.exports().names)
            assert package.exports().isAvailable and not package.exports().isCyclic
            assert package.unavailableFiles() == []
            file_id = a.fileId('src/semantic_api.cj')
            text = a.text('src/semantic_api.cj')
            offset = text.encode().index(b'identity(shared())')
            occurrence = s.at(file_id, offset)
            assert isinstance(occurrence, SemanticOccurrence)
            assert 'analysis' not in dir(occurrence)
            file = occurrence.contextualFile()
            assert isinstance(file, SemanticFile) and not file.isTest()
            assert file.imports() == []
            assert any(b.name == 'identity' for b in file.visibleNames())
            assert isinstance(file.lookup('identity', Namespace.Values()), Resolution)
            assert file.conditions() == []
            assert isinstance(file.whenStatus(), WhenDiagnostics)
            resolution = occurrence.resolution()
            assert resolution.status == SemanticResolutionStatus.ResolvedMeaning()
            call = resolution.call
            assert isinstance(call, SemanticCallResolution)
            missing = s.at(file_id, text.encode().index(b'noSemanticTarget')).resolution()
            assert missing.status == SemanticResolutionStatus.UnresolvedMeaning()
            assert isinstance(missing.reason, SemanticResolutionReason)
            assert call.status == SemanticResolutionStatus.ResolvedMeaning()
            assert call.signature().display() == '(Int64) -> Int64'
            assert call.argumentParameters() == [0]
            assert not call.isSetter
            assert len(call.bindings()) == 1
            binding = call.bindings()[0]
            assert isinstance(binding, SemanticGenericBinding)
            assert binding.valueType.display() == 'Int64'
            target = call.callable()
            assert target.contextualPackage().identity == package.identity
            assert isinstance(target.identity, SemanticIdentity.NamedIdentity)
            assert target.identity == target.identity
            assert call.callee.semanticType().display() == '(Int64) -> Int64'
            assert isinstance(binding.valueType.kind(), SemanticTypeKind.PrimitiveType)
            location = occurrence.location
            assert location.kind() == SemanticSourceKind.PhysicalSource()
            assert location.excerpt() == 'identity'
            assert location.sourceText() == text
            assert location.coordinates()[0] == 5
            assert location.contextualFile().identity == file.identity
            tree = s.syntaxAt(file_id)
            assert isinstance(tree, SemanticSyntaxTree) and tree.errors() == []
            syntax = tree.root()
            assert syntax.kindName() and syntax.text() == text
            assert tree.resolve(syntax.pointer()).text() == text
            foreign = a.semantic().syntaxAt(file_id)
            try:
                foreign.resolve(syntax.pointer())
            except RuntimeError as error:
                assert 'another analysis' in str(error), str(error)
            else:
                raise AssertionError('foreign syntax pointer was accepted')
            try:
                SemanticObject(s, target.identity)
            except TypeError:
                pass
            else:
                raise AssertionError('snapshot constructor was exported')
            assert any(e.isToken() for e in syntax.descendants())
            origins = target.syntaxOrigins()
            assert origins and isinstance(origins[0], SemanticSyntaxOrigin.SourceSyntax)
            declaration = origins[0].field0
            assert any(m.object.identity == target.identity for m in declaration.mappings())
            assert isinstance(target.origins()[0], SemanticOrigin.SourceOrigin)
            incoming = target.incomingCalls()
            assert incoming and all(isinstance(e, SemanticCallEdge) for e in incoming)
            assert any(e.caller.identity == occurrence.owner.identity for e in incoming)
            assert isinstance(occurrence.owner.outgoingCalls(), SemanticCalls)
            assert isinstance(target.usages(), SemanticUsages)
            assert isinstance(occurrence.owner.bodyResolutions(), SemanticBodyResolutions)
            assert occurrence.owner.calls() and occurrence.owner.resolutions()
            child_offset = text.encode().index(b'SemanticChild')
            child = s.at(file_id, child_offset).definitions[0]
            bases = child.directSupertypes()
            assert len(bases) == 1 and isinstance(bases[0], SemanticHierarchyEdge)
            base = bases[0].supertype
            assert any(e.subtype.identity == child.identity for e in base.directSubtypes())
            member = s.at(file_id, text.encode().rindex(b'value():')).definitions[0]
            implementations = member.directImplementations()
            assert len(implementations) == 1
            edge = implementations[0]
            assert isinstance(edge, SemanticImplementationEdge)
            assert edge.implementation.identity == member.identity
            assert any(e.implementation.identity == member.identity
                       for e in edge.declaration.directImplementers())
            owner = next(d for d in a.declarations('src/semantic_api.cj')
                         if 'semanticUse' in a.item(d).names)
            inferred = a.infer(owner)
            source_map = a.loweredBody(owner).sourceMap
            for i, origin in enumerate(source_map.exprs):
                if origin.written is not None:
                    assert ExprId(i) in source_map.exprsAtSource(origin.written)
                    assert any(source.range == origin.written.range
                               for source in source_map.sourcesOfExpr(ExprId(i)))
            raw = next(c for c in inferred.calls if c.bindings)
            assert isinstance(raw, CallResolution)
            assert raw.outcome == CallResolutionOutcome.Resolved()
            assert raw == inferred.callOf(raw.expr)
            assert isinstance(raw.bindings[0], GenericBinding)
            assert raw.bindings[0] == inferred.callOf(raw.expr).bindings[0]
            assert a.typeText(raw.bindings[0].ty) == 'Int64'
            sys.modules['_semantic_exports_hold'] = types.SimpleNamespace(
                project=project, target=target, location=location, tree=tree,
                syntax=syntax, pointer=syntax.pointer(), file=file, s=s)
            result = True
        """)
        # assert
        self.assertTrue(checked['result'])

        # act - keep native objects across calls, then invalidate their snapshot.
        path.write_text(path.read_text() + '// changed revision\n', encoding='utf-8')
        stale = run("""
            import sys
            held = sys.modules.pop('_semantic_exports_hold')
            operations = [held.project.modules, held.target.calls, held.location.sourceText,
                          held.syntax.children, held.file.visibleNames,
                          lambda: held.tree.resolve(held.pointer)]
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
        path.unlink()
