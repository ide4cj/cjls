package loupe

import std.collection.*
import ginkgo.TextRange
import loupe.db.Cfg
import loupe.hir.*

/** A name and its semantic target; site retains the available immediate import provenance. */
public class SemanticBinding {
    SemanticBinding(
        public let name: String,
        public let target: SemanticObject,
        public let visibility: Visibility,
        public let site: ?ImportSite,
        public let stage: ScopeStage,
        public let implicitImport!: ?SemanticImplicitImport = None
    ) {}
}

/** Export cycles are distinct from a known empty exported-name collection. */
public class SemanticExports {
    SemanticExports(
        public let names: Array<SemanticBinding>,
        public let cyclic: Bool,
        /** False for unloaded source inputs or an unreadable binary; names may be partial. */
        public let isAvailable: Bool
    ) {}
}

/** One active import path, its alias/glob, visibility, stage and contextual syntax site. */
public class SemanticImport {
    SemanticImport(
        public let file: SemanticFile,
        public let path: ImportPath,
        public let site: ImportSite,
        public let stage: ScopeStage,
        public let target: ?SemanticPackage,
        public let names: Array<SemanticBinding>,
        public let error: ?ImportError
    ) {}

    public prop isReExport: Bool {
        get() {
            site.level != Visibility.Private
        }
    }

    /** Exact import declaration when syntax is available; site.path indexes grouped paths. */
    public func location(): ?SemanticLocation {
        let db = file.analysis.db
        db.unwindIfCancelled()
        let (root, ids) = syntaxOf(db, site.file) ?? return None
        let node = ids.node(site.item, root) ?? return None
        file.analysis.location(site.file, node.textRange, node.textRange)
    }
}

/** An implicit glob kept separate from written imports and dependency permissions. */
public class SemanticImplicitImport {
    SemanticImplicitImport(public let target: SemanticPackage, public let isTestImport: Bool) {}
}

/** Condition evidence includes unknown evaluations independently of loaded-active filtering. */
public class SemanticCondition {
    SemanticCondition(
        public let location: SemanticLocation,
        public let expression: CfgExpr,
        public let evaluation: ?Bool,
        public let reasons: Array<String>
    ) {}
}

/** File identity retains ordinary/test/script, attachment and expansion context. */
public class SemanticFile {
    SemanticFile(let analysis: SemanticAnalysis, public let identity: ItemFile) {}

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

    public func at(offset: Int64): ?SemanticOccurrence {
        analysis.inFile(identity, offset)
    }

    public func isTest(): Bool {
        let db = analysis.db
        db.unwindIfCancelled()
        let pkg = contextualPackage() ?? return false
        isTestOf(db, pkg.identity, identity)
    }

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
                    result.add(
                        SemanticImport(
                            this,
                            path,
                            site,
                            stage,
                            target.map { id => SemanticPackage(analysis, id) },
                            names.toArray(),
                            error
                        )
                    )
                }
            }
        }
        Some(result.toArray())
    }

    public func implicitImports(): ?Array<SemanticImplicitImport> {
        let db = analysis.db
        db.unwindIfCancelled()
        let file = scopeFileOf(db, identity) ?? return None
        let pkg = packageOfFile(db, file) ?? return None
        let result = ArrayList<SemanticImplicitImport>()
        if (let Some(glob) <- preludeOf(db, pkg)) {
            result.add(SemanticImplicitImport(SemanticPackage(analysis, glob.pkg), false))
        }
        for (glob in testImportsOf(db, pkg, file)) {
            result.add(SemanticImplicitImport(SemanticPackage(analysis, glob.pkg), true))
        }
        Some(result.toArray())
    }

    /**
     * Package/file scope candidates, excluding lexical locals and members. Separate entries
     * preserve competing import routes; lookup(name, namespace) applies semantic precedence.
     */
    public func visibleNames(stage!: ScopeStage = ScopeStage.Expanded): ?Array<SemanticBinding> {
        let db = analysis.db
        db.unwindIfCancelled()
        let source = scopeFileOf(db, identity) ?? return None
        let pkg = packageOfFile(db, source) ?? return None
        let own = defMapAt(db, PackageRef.Source(pkg), stage)
        let imports = importsAt(db, pkg, source, stage)
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
                let exports = exportsAt(db, glob.pkg, stage)
                for (map in [exports.names, exports.ctors]) {
                    for ((name, defs) in map) {
                        for (id in visibleOf(defs, glob.relation, glob.level)) {
                            let implicit =
                                if (glob.site.isNone()) {
                                    Some(
                                        SemanticImplicitImport(
                                            SemanticPackage(analysis, glob.pkg),
                                            testImportsOf(db, pkg, source)
                                                .iterator()
                                                .any { one => one.pkg == glob.pkg }
                                        )
                                    )
                                } else {
                                    None<SemanticImplicitImport>
                                }
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
        }
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
                    let target = analysis.object(NamedIdentity(Definition.DeclDef(ctor)))
                    if (
                        !result
                            .iterator()
                            .any {
                                one =>
                                one.name == name && one.target.identity == target.identity
                            }
                    ) {
                        result.add(SemanticBinding(name, target, Visibility.Private, None, stage))
                    }
                }
            }
            for (glob in level.globs) {
                for ((name, defs) in exportsAt(db, glob.pkg, stage).ctors) {
                    for (ctor in visibleOf(defs, glob.relation, glob.level)) {
                        let target = analysis.object(NamedIdentity(Definition.DeclDef(ctor)))
                        if (
                            !result
                                .iterator()
                                .any {
                                    one =>
                                    one.name == name && one.target.identity == target.identity
                                }
                        ) {
                            result.add(SemanticBinding(name, target, glob.level, glob.site, stage))
                        }
                    }
                }
            }
        }
        Some(result.toArray())
    }

    func importBinding(name: String, imported: Imported, stage: ScopeStage): SemanticBinding {
        let definition =
            match (imported.target) {
                case OfDecl(id) => Definition.DeclDef(id)
                case OfPackage(pkg) => Definition.PackageDef(pkg)
            }
        SemanticBinding(
            name,
            analysis.object(NamedIdentity(definition)),
            imported.site.map { site => site.level } ?? Visibility.Private,
            imported.site,
            stage
        )
    }

    /** Exact package/file lookup, preserving ambiguity through the existing Resolution value. */
    public func lookup(name: String, namespace: Namespace): ?Resolution {
        let db = analysis.db
        db.unwindIfCancelled()
        let source = scopeFileOf(db, identity) ?? return None
        let pkg = packageOfFile(db, source) ?? return None
        Some(lookUp(db, pkg, source, name, namespace))
    }

    /** All written @When conditions, including nested and unknown ones, with revision text. */
    public func conditions(): ?Array<SemanticCondition> {
        let db = analysis.db
        db.unwindIfCancelled()
        let cfg = configuration()?.cfg ?? return None
        let (root, _) = syntaxOf(db, identity) ?? return None
        let result = ArrayList<SemanticCondition>()
        for (node in root.descendants()) {
            if (let Some(condition) <- conditionOf(node)) {
                result.add(
                    SemanticCondition(
                        analysis.location(identity, node.textRange, node.textRange),
                        condition,
                        condition.evaluate(cfg),
                        condition.whyFalse(cfg)
                    )
                )
            }
        }
        Some(result.toArray())
    }

    /** Outermost inactive ranges and invalid-condition diagnostics; none without source text. */
    public func whenStatus(): ?WhenDiagnostics {
        let db = analysis.db
        db.unwindIfCancelled()
        match (identity) {
            case Source(source) => Some(whenDiagnostics(db, source))
            case _ => None
        }
    }
}
