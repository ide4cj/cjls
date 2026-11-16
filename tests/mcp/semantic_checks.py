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
            self._check_python_metadata(run)
            self._check_semantic_discovery(run)
            self._check_semantic_project(run)
            self._check_semantic_scope(run)
            self._check_semantic_resolution(run)
            self._check_semantic_location(run)
            self._check_semantic_syntax(run)
            self._check_semantic_relationships(run)
            self._check_semantic_inference(run)
            self._check_semantic_staleness(path, run)
            self._check_project_build_inputs(root, run)
        finally:
            path.unlink()

    def _check_python_metadata(self, run):
        checked = run("""
            a = workspace.analysis()
            exported = {name: value for name, value in globals().items() if isinstance(value, type)}
            assert len(exported) >= 200
            missing = [name for name, cls in exported.items() if not cls.__doc__]
            renamed = [(name, cls.__name__) for name, cls in exported.items() if name != cls.__name__]
            assert not missing, missing
            assert not renamed, renamed
            undocumented_methods = [(owner, name) for owner, cls in exported.items()
                                    for name, value in vars(cls).items()
                                    if not name.startswith('_') and name not in ('hashCode', 'toString')
                                    and callable(value) and not isinstance(value, type) and not value.__doc__]
            assert not undocumented_methods, undocumented_methods
            assert type(workspace).__doc__
            assert 'UTF-8' in TextRange.__doc__
            assert 'end` excluded' in TextRange.contains.__doc__
            assert 'syntax errors' in AnalysisRevision.formatting.__doc__
            assert 'return type' in SignatureTypes.ty.__doc__
            assert 'Higher first' in CompletionItem.relevance.__doc__
            assert SemanticSyntaxElement.descendants.__doc__
            assert SemanticObject.contextualPackage.__doc__
            definition = a.declarations('src/helper.cj')[0]
            duplicate = Redefinition(definition, 'duplicate')
            missing_specific = NoSpecific(definition, 'unavailable')
            assert duplicate.definition == definition
            assert missing_specific.definition == definition
            assert Redefinition.__match_args__ == ('definition', 'name')
            assert NoSpecific.__match_args__ == ('definition', 'message')
            result = len(exported)
        """)
        self.assertGreaterEqual(checked['result'], 200)

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

    def _check_project_build_inputs(self, root, run):
        manifest = root / 'cjpm.toml'
        before = manifest.read_text()
        manifest.write_text(before + '\n[ffi.c.sample_native]\npath = "native-libs"\n')
        try:
            checked = run("""
                import sys, types
                a = workspace.analysis()
                module = next(m for m in a.semantic().project().modules() if m.isWorkspaceMember())
                libraries = module.nativeLibraries()
                assert len(libraries) == 1
                library = libraries[0]
                expected = NativeLibrary('sample_native', VfsPath.file(workspace.root).join('native-libs'))
                assert library == expected and hash(library) == hash(expected)
                assert library.name == 'sample_native' and library.dir == expected.dir
                assert module.dependencies() and not any(d.name == library.name for d in module.dependencies())
                try:
                    library.name = 'changed'
                except AttributeError:
                    pass
                else:
                    raise AssertionError('native linker inputs must be read-only')
                assert 'native linker' in NativeLibrary.__doc__
                assert 'linker' in SemanticModule.nativeLibraries.__doc__
                sys.modules['_native_inputs_hold'] = types.SimpleNamespace(module=module)
                result = True
            """)
            self.assertTrue(checked['result'])
            self._check_sdk_export(run)
            self._check_sdk_revision(run)
        finally:
            manifest.write_text(before)
        restored = run("""
            import sys
            stale = sys.modules.pop('_native_inputs_hold').module
            try:
                stale.nativeLibraries()
            except RuntimeError:
                pass
            else:
                raise AssertionError('stale native library query was accepted')
            project = workspace.analysis().semantic().project()
            assert all(not m.nativeLibraries() for m in project.modules() if m.isWorkspaceMember())
            result = True
        """)
        self.assertTrue(restored['result'])

    def _check_sdk_export(self, run):
        checked = run("""
            a = workspace.analysis()
            sdk = workspace.sdk
            if sdk is not None:
                assert isinstance(sdk, CangjieHome) and sdk.path and sdk.source
                assert (sdk.version is None) == (sdk.channel is None)
                assert sdk.channel in [None, 'LTS', 'STS', 'pinned nightly', 'out of window']
                assert sdk == CangjieHome(sdk.path, sdk.source, version=sdk.version)
            unknown = CangjieHome('/sdk', 'test')
            assert unknown.version is None and unknown.channel is None
            lts = CangjieHome('/sdk', 'test', version='1.0.5')
            assert lts.channel == 'LTS' and lts != unknown
            assert hash(lts) == hash(CangjieHome('/sdk', 'test', version='1.0.5'))
            assert CangjieHome('/sdk', 'test', version='0.0.0').channel == 'out of window'
            assert 'selected SDK' in CangjieHome.__doc__
            for cls, name in [(Location, 'Location'), (BodySource, 'BodySource'),
                              (LoweredSignature, 'LoweredSignature'),
                              (SignatureSourceMap, 'SignatureSourceMap')]:
                assert cls.__name__ == name, (cls.__name__, name)
                assert cls.__doc__, name
            result = True
        """)
        self.assertTrue(checked['result'])

    def _check_sdk_revision(self, run):
        selected = run("""
            import os, sys, types
            from pathlib import Path
            a = workspace.analysis()
            sdk = workspace.sdk
            fake = Path(workspace.root, '.codex', 'sdk-export')
            (fake / 'bin').mkdir(parents=True)
            compiler = fake / 'bin/cjc'
            compiler.write_text('#!/bin/sh\\nprintf "Cangjie Compiler: 2.0.0 (cjnative)\\\\n"\\n')
            compiler.chmod(0o755)
            held = types.SimpleNamespace(a=a, sdk=sdk, original=os.environ.get('CANGJIE_HOME'))
            sys.modules['_sdk_inputs_hold'] = held
            os.environ['CANGJIE_HOME'] = str(fake)
            assert workspace.sdk == sdk
            result = a.revision
        """)
        try:
            changed = run("""
                import os, sys
                held = sys.modules['_sdk_inputs_hold']
                a = workspace.analysis()
                try:
                    sdk = workspace.sdk
                    assert sdk.path.endswith('/.codex/sdk-export')
                    assert sdk.source == 'CANGJIE_HOME'
                    assert sdk.version == '2.0.0' and sdk.channel == 'out of window'
                    try:
                        held.a.fileSymbols('src/helper.cj')
                    except RuntimeError:
                        pass
                    else:
                        raise AssertionError('changing the SDK must invalidate retained analysis')
                    result = a.revision
                finally:
                    if held.original is None:
                        os.environ.pop('CANGJIE_HOME', None)
                    else:
                        os.environ['CANGJIE_HOME'] = held.original
            """)
            self.assertGreater(changed['revision'], selected['revision'])
        finally:
            restored = run("""
                import os, sys
                held = sys.modules.pop('_sdk_inputs_hold')
                if held.original is None:
                    os.environ.pop('CANGJIE_HOME', None)
                else:
                    os.environ['CANGJIE_HOME'] = held.original
                assert workspace.sdk == held.sdk
                result = workspace.revision
            """)
            self.assertGreater(restored['revision'], selected['revision'])
