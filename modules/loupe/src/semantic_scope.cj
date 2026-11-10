package loupe

import std.collection.{ArrayList, collectArray, filterMap}
import py_interop.*
import py_interop.internal_macros.DerivePython
import loupe.db.{Package, SourceFile}
import loupe.hir.{
    CfgExpr,
    DefId,
    Glob,
    ImportError,
    ImportPath,
    ImportSite,
    Imported,
    ItemFile,
    ItemKind,
    Namespace,
    PackageRef,
    Resolution,
    ScopeStage,
    Visibility,
    WhenDiagnostics,
    cfgOfFile,
    conditionOf,
    defMapAt,
    expansionsOf,
    exportsAt,
    fileImportsAt,
    importLevelOf,
    importsAt,
    isTestOf,
    itemTreeOf,
    lookUp,
    packageOfFile,
    preludeOf,
    resolutionFile,
    resolutionPackage,
    resolveImport,
    scopeFileOf,
    syntaxOf,
    targetOf,
    testImportsOf,
    visibleOf,
    whenDiagnostics
}

/**
 * A name and its semantic target; site retains the available immediate import provenance.
 */
@DerivePython
@PyDoc["A name and its semantic target; site retains the available immediate import provenance."]
public struct SemanticBinding {
    SemanticBinding(
        public let name: String,
        public let target: SemanticObject,
        public let visibility: Visibility,
        public let site: ?ImportSite,
        public let stage: ScopeStage,
        public let implicitImport!: ?SemanticImplicitImport = None
    ) {}
}

/**
 * Export cycles are distinct from a known empty exported-name collection.
 */
@DerivePython
@PyDoc["Export cycles are distinct from a known empty exported-name collection."]
public struct SemanticExports {
    SemanticExports(
        public let names: Array<SemanticBinding>,
        public let isCyclic!: Bool,
        /**
         * False for unloaded source inputs or an unreadable binary; names may be partial.
         */
        @PyDoc["False for unloaded source inputs or an unreadable binary; names may be partial."]
        public let isAvailable!: Bool
    ) {}
}

/**
 * One active import path, its alias/glob, visibility, stage and contextual syntax site.
 */
@DerivePython
@PyDoc["One active import path, its alias/glob, visibility, stage and contextual syntax site."]
public struct SemanticImport {
    SemanticImport(
        public let file: SemanticFile,
        public let path: ImportPath,
        public let site: ImportSite,
        public let stage: ScopeStage,
        public let target: ?SemanticPackage,
        public let names: Array<SemanticBinding>,
        public let error: ?ImportError
    ) {}

    @PyDoc["Whether this written import re-exports its targets."]
    public prop isReExport: Bool {
        get() {
            site.level != Visibility.Private
        }
    }

    /**
     * Exact import declaration when syntax is available; site.path indexes grouped paths.
     */
    @PyDoc["Exact import declaration when syntax is available; site.path indexes grouped paths."]
    public func location(): ?SemanticLocation {
        let db = file.analysis.db
        db.unwindIfCancelled()
        let (root, ids) = syntaxOf(db, site.file) ?? return None
        let node = ids.node(site.item, root) ?? return None
        file.analysis.location(site.file, node.textRange, node.textRange)
    }
}

/**
 * An implicit glob kept separate from written imports and dependency permissions.
 */
@DerivePython
@PyDoc["An implicit glob kept separate from written imports and dependency permissions."]
public struct SemanticImplicitImport {
    SemanticImplicitImport(public let target: SemanticPackage, public let isTestImport!: Bool) {}
}

/**
 * Condition evidence includes unknown evaluations independently of loaded-active filtering.
 */
@DerivePython
@PyDoc["Condition evidence includes unknown evaluations independently of loaded-active filtering."]
public struct SemanticCondition {
    SemanticCondition(
        public let location: SemanticLocation,
        public let expression: CfgExpr,
        public let evaluation: ?Bool,
        public let reasons: Array<String>
    ) {}
}

/**
 * File identity retains ordinary/test/script, attachment and expansion context.
 */
@DerivePython
@PyDoc["File identity retains ordinary/test/script, attachment and expansion context."]
public class SemanticFile {
    @PyIgnore
    let analysis: SemanticAnalysis
    public let identity: ItemFile

    @PyIgnore
    init(analysis: SemanticAnalysis, identity: ItemFile) {
        this.analysis = analysis
        this.identity = identity
    }

    @PyDoc["Return the package used to resolve names in this file, or None when unavailable."]
    public func contextualPackage(): ?SemanticPackage {
        let db = analysis.db
        db.unwindIfCancelled()
        match (identity) {
            case Binary(pkg, _) => SemanticPackage(analysis, PackageRef.Binary(pkg))
            case CompilerBuiltIns(pkg) => SemanticPackage(analysis, PackageRef.Source(pkg))
            case _ =>
                scopeFileOf(db, identity)
                    .flatMap { file => packageOfFile(db, file) }
                    .map { pkg => SemanticPackage(analysis, PackageRef.Source(pkg)) }
        }
    }

    @PyDoc["Find a semantic occurrence at a UTF-8 byte offset in this contextual file."]
    public func at(offset: Int64): ?SemanticOccurrence {
        analysis.inFile(identity, offset)
    }

    @PyDoc["Whether this file is analyzed with its package test-import permissions."]
    public func isTest(): Bool {
        let db = analysis.db
        db.unwindIfCancelled()
        let pkg = contextualPackage() ?? return false
        isTestOf(db, pkg.identity, identity)
    }

    @PyDoc["Return this source context configuration, or None when unavailable."]
    public func configuration(): ?SemanticConfiguration {
        let db = analysis.db
        db.unwindIfCancelled()
        scopeFileOf(db, identity).map { file => SemanticConfiguration(cfgOfFile(db, file)) }
    }

    /**
     * Written-stage reads this file only; expanded-stage also includes its expansion imports.
     * Target resolution reads exports at the requested stage. Unresolved paths retain errors.
     * Binary source syntax is unavailable even if its compiled item tree has no imports.
     */
    @PyDoc["Written-stage reads this file only; expanded-stage also includes its expansion imports. Target resolution reads exports at the requested stage. Unresolved paths retain errors. Binary source syntax is unavailable even if its compiled item tree has no imports."]
    public func imports(stage!: ScopeStage = ScopeStage.Written): ?Array<SemanticImport> {
        let db = analysis.db
        db.unwindIfCancelled()
        if (let Binary(_, _) <- identity) {
            return None
        }
        if (let CompilerBuiltIns(_) <- identity) {
            return None
        }
        let pkg = contextualPackage() ?? return None
        let from =
            match (pkg.identity) {
                case Source(source) => resolutionPackage(db, source)
                case _ => pkg.identity
            }
        let files =
            if (stage == ScopeStage.Expanded) {
                [identity].concat(expansionsOf(db, identity))
            } else {
                [identity]
            }
        let result = ArrayList<SemanticImport>()
        for (file in files) {
            for (item in itemTreeOf(db, file).imports) {
                let level = importLevelOf(item)
                for (i in 0..item.paths.size) {
                    let path = item.paths[i]
                    let site = ImportSite(file, item.id, i, level)
                    result.add(resolveWrittenImport(from, path, site, stage))
                }
            }
        }
        Some(result.toArray())
    }

    private func resolveWrittenImport(
        from: PackageRef,
        path: ImportPath,
        site: ImportSite,
        stage: ScopeStage
    ): SemanticImport {
        let db = analysis.db
        let level = site.level
        let target =
            match (targetOf(db, from, path, level, ofTests: isTest())) {
                case PackageOf(_, target) => Some(target)
                case GlobOf(target, _) => Some(target)
                case NameOf(target, _, _, _) => Some(target)
                case _ => None<PackageRef>
            }
        let names = ArrayList<SemanticBinding>()
        var error: ?ImportError = None
        match (resolveImport(db, from, path, level, ofTests: isTest(), stage: stage)) {
            case ToPackage(name, target) =>
                names.add(
                    SemanticBinding(
                        name,
                        analysis.object(NamedIdentity(Definition.PackageDef(target))),
                        level,
                        site,
                        stage
                    )
                )
            case ToNames(_, brought) =>
                for ((name, defs) in brought) {
                    for (id in defs) {
                        names.add(
                            SemanticBinding(
                                name,
                                analysis.object(NamedIdentity(Definition.DeclDef(id))),
                                level,
                                site,
                                stage
                            )
                        )
                    }
                }
            case Unresolved(reason) => error = reason
        }
        SemanticImport(
            this,
            path,
            site,
            stage,
            target.map { id => SemanticPackage(analysis, id) },
            names.toArray(),
            error
        )
    }

    @PyDoc["Return prelude and test imports; None means the source context is unavailable."]
    public func implicitImports(): ?Array<SemanticImplicitImport> {
        let db = analysis.db
        db.unwindIfCancelled()
        let file = scopeFileOf(db, identity) ?? return None
        let pkg = packageOfFile(db, file) ?? return None
        let result = ArrayList<SemanticImplicitImport>()
        if (let Some(glob) <- preludeOf(db, pkg)) {
            result.add(
                SemanticImplicitImport(SemanticPackage(analysis, glob.pkg), isTestImport: false)
            )
        }
        result.add(
            all: testImportsOf(db, pkg, file)
                .map {
                    glob =>
                    SemanticImplicitImport(SemanticPackage(analysis, glob.pkg), isTestImport: true)
                }
        )
        Some(result.toArray())
    }

    /**
     * Package/file scope candidates, excluding lexical locals and members. Separate entries
     * preserve competing import routes; lookup(name, namespace) applies semantic precedence.
     */
    @PyDoc["Package/file scope candidates, excluding lexical locals and members. Separate entries preserve competing import routes; lookup(name, namespace) applies semantic precedence."]
    public func visibleNames(stage!: ScopeStage = ScopeStage.Expanded): ?Array<SemanticBinding> {
        let db = analysis.db
        db.unwindIfCancelled()
        let source = scopeFileOf(db, identity) ?? return None
        let pkg = packageOfFile(db, source) ?? return None
        let result = ArrayList(ownBindings(pkg, source, stage))
        addImportedBindings(result, pkg, source, stage)
        addSiblingConstructors(result, pkg, source, stage)
        Some(result.toArray())
    }

    private func ownBindings(
        pkg: Package,
        source: SourceFile,
        stage: ScopeStage
    ): Array<SemanticBinding> {
        let db = analysis.db
        let own = defMapAt(db, PackageRef.Source(pkg), stage)
        let result = ArrayList<SemanticBinding>()
        for (map in [own.names, own.ctors]) {
            for ((name, defs) in map) {
                for (
                    def in defs where def.visibility != Visibility.Private ||
                        def.id.file(db) == identity ||
                        def.id.file(db) == resolutionFile(db, source) ||
                        def.id.item(db).kind == ItemKind.EnumCtor
                ) {
                    result.add(
                        SemanticBinding(
                            name,
                            analysis.object(NamedIdentity(Definition.DeclDef(def.id))),
                            def.visibility,
                            None,
                            stage
                        )
                    )
                }
            }
        }
        result.toArray()
    }

    private func addImportedBindings(
        result: ArrayList<SemanticBinding>,
        pkg: Package,
        source: SourceFile,
        stage: ScopeStage
    ): Unit {
        let db = analysis.db
        let imports = importsAt(db, pkg, source, stage)
        for (level in [imports.file, imports.pkg]) {
            for ((name, entries) in level.names) {
                for (entry in entries) {
                    result.add(importBinding(name, entry, stage))
                }
            }
            for ((name, ids) in level.ctors) {
                for (id in ids) {
                    result.add(
                        SemanticBinding(
                            name,
                            analysis.object(NamedIdentity(Definition.DeclDef(id))),
                            Visibility.Private,
                            None,
                            stage
                        )
                    )
                }
            }
            for (glob in level.globs) {
                addGlobBindings(result, glob, pkg, source, stage)
            }
        }
    }

    private func addGlobBindings(
        result: ArrayList<SemanticBinding>,
        glob: Glob,
        pkg: Package,
        source: SourceFile,
        stage: ScopeStage
    ): Unit {
        let db = analysis.db
        let exports = exportsAt(db, glob.pkg, stage)
        let implicit =
            if (glob.site.isNone()) {
                Some(
                    SemanticImplicitImport(
                        SemanticPackage(analysis, glob.pkg),
                        isTestImport: testImportsOf(db, pkg, source)
                            .iterator()
                            .any { one => one.pkg == glob.pkg }
                    )
                )
            } else {
                None<SemanticImplicitImport>
            }
        for (map in [exports.names, exports.ctors]) {
            for ((name, defs) in map) {
                for (id in visibleOf(defs, glob.relation, glob.level)) {
                    result.add(
                        SemanticBinding(
                            name,
                            analysis.object(NamedIdentity(Definition.DeclDef(id))),
                            glob.level,
                            glob.site,
                            stage,
                            implicitImport: implicit
                        )
                    )
                }
            }
        }
    }

    private func addSiblingConstructors(
        result: ArrayList<SemanticBinding>,
        pkg: Package,
        source: SourceFile,
        stage: ScopeStage
    ): Unit {
        let db = analysis.db
        // Enum constructors imported by another file have package scope (N73). Read
        // each contextual file at the requested stage; the shared constructor index is expanded.
        for (id in pkg.files(db) where isTest() || !pkg.testFiles(db).contains(id)) {
            let other = db.sourceFile(id, context: pkg) ?? continue
            if (other == source) {
                continue
            }
            let level = fileImportsAt(db, pkg, other, stage)
            for ((name, ids) in level.ctors) {
                for (ctor in ids) {
                    addDistinctConstructor(result, name, ctor, Visibility.Private, None, stage)
                }
            }
            for (glob in level.globs) {
                for ((name, defs) in exportsAt(db, glob.pkg, stage).ctors) {
                    for (ctor in visibleOf(defs, glob.relation, glob.level)) {
                        addDistinctConstructor(result, name, ctor, glob.level, glob.site, stage)
                    }
                }
            }
        }
    }

    private func addDistinctConstructor(
        result: ArrayList<SemanticBinding>,
        name: String,
        id: DefId,
        visibility: Visibility,
        site: ?ImportSite,
        stage: ScopeStage
    ): Unit {
        let target = analysis.object(NamedIdentity(Definition.DeclDef(id)))
        if (
            !result
                .iterator()
                .any { one => one.name == name && one.target.identity == target.identity }
        ) {
            result.add(SemanticBinding(name, target, visibility, site, stage))
        }
    }

    private func importBinding(
        name: String,
        imported: Imported,
        stage: ScopeStage
    ): SemanticBinding {
        let definition =
            match (imported.target) {
                case OfDecl(id) => Definition.DeclDef(id)
                case OfPackage(pkg) => Definition.PackageDef(pkg)
            }
        SemanticBinding(
            name,
            analysis.object(NamedIdentity(definition)),
            imported.site?.level ?? Visibility.Private,
            imported.site,
            stage
        )
    }

    /**
     * Exact package/file lookup, preserving ambiguity through the existing Resolution value.
     */
    @PyDoc["Exact package/file lookup, preserving ambiguity through the existing Resolution value."]
    public func lookup(name: String, namespace: Namespace): ?Resolution {
        let db = analysis.db
        db.unwindIfCancelled()
        let source = scopeFileOf(db, identity) ?? return None
        let pkg = packageOfFile(db, source) ?? return None
        Some(lookUp(db, pkg, source, name, namespace))
    }

    /**
     * All written @When conditions, including nested and unknown ones, with revision text.
     */
    @PyDoc["All written @When conditions, including nested and unknown ones, with revision text."]
    public func conditions(): ?Array<SemanticCondition> {
        let db = analysis.db
        db.unwindIfCancelled()
        let cfg = configuration()?.cfg ?? return None
        let (root, _) = syntaxOf(db, identity) ?? return None
        Some(
            root.descendants() |>
                filterMap {
                    node =>
                    conditionOf(node)
                        .map {
                            condition =>
                            SemanticCondition(
                                analysis.location(identity, node.textRange, node.textRange),
                                condition,
                                condition.evaluate(cfg),
                                condition.whyFalse(cfg)
                            )
                        }
                } |>
                collectArray
        )
    }

    /**
     * Outermost inactive ranges and invalid-condition diagnostics; none without source text.
     */
    @PyDoc["Outermost inactive ranges and invalid-condition diagnostics; none without source text."]
    public func whenStatus(): ?WhenDiagnostics {
        let db = analysis.db
        db.unwindIfCancelled()
        match (identity) {
            case Source(source) => Some(whenDiagnostics(db, source))
            case _ => None
        }
    }
}
