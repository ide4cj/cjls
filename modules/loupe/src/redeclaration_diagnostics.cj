package loupe

import std.collection.*
import calca.*
import calca.macros.*
import cjsyntax.{CjSyntaxNode, SyntaxKind}
import cjsyntax.ast.{AnyHasName, FuncDecl, InitDecl, Name, Param, Pattern, VarDecl}
import ginkgo.SyntaxNodePtr
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.hir.*
import loupe.syntax.parse

/**
 * Collisions are checked in declaration scopes, rather than lookup scopes: each sequential
 * local opens a lookup scope, but cannot redeclare an earlier local in the same block.
 */
@CalcaTracked
func redeclarationDiagnostics(db: AnalysisDatabase, source: SourceFile): Array<Diagnostic> {
    let file = ItemFile.Source(source)
    let root = parse(db, source).syntaxNode()
    let active = ActiveFilter.of(db, source)
    let replaced = readServerCallsOf(db, source)
    let ids = itemIdMap(db, source)
    let found = ArrayList<Diagnostic>()
    let previous = ArrayList<(ItemFile, Item)>()
    if (let Some(pkg) <- packageOfFile(db, source) && pkg.binary(db).isNone()) {
        for (other in filesOf(db, PackageRef.Source(pkg))) {
            if (other == file) {
                break
            }
            for (item in itemTreeOf(db, other).items) {
                previous.add((other, item))
            }
        }
    }
    checkItemRedeclarations(db, file, itemTreeOf(db, file).items, previous, root, found)

    func visit(node: CjSyntaxNode): Unit {
        if (!declarationDefinitelyActive(node, active) || node.kind == SyntaxKind.MacroExpandDecl) {
            return
        }
        if (let Some(id) <- ids.idAround(node) && replaced.any { call => call.item(db) == id }) {
            return
        }
        if (node.kind == SyntaxKind.Block || node.kind == SyntaxKind.LambdaExpr) {
            let names = HashMap<String, Array<CjSyntaxNode>>()
            // Parameters and the outermost function body share a declaration scope in cjc.
            if (node.kind == SyntaxKind.Block && let Some(parent) <- node.parent) {
                for (list in parent.children() where list.kind == SyntaxKind.ParamList) {
                    for (
                        param in list.children() where param.kind == SyntaxKind.Param &&
                            declarationDefinitelyActive(param, active)
                    ) {
                        addLocalDeclaration(db, file, param, names, found, report: false)
                    }
                }
            }
            for (child in node.children() where declarationDefinitelyActive(child, active)) {
                if (child.kind == SyntaxKind.LambdaParamList) {
                    for (param in child.children()) {
                        addLocalDeclaration(db, file, param, names, found)
                    }
                } else {
                    addLocalDeclaration(db, file, child, names, found)
                }
            }
        }
        if (node.kind == SyntaxKind.ParamList) {
            let names = HashMap<String, Array<CjSyntaxNode>>()
            for (
                param in node.children() where param.kind == SyntaxKind.Param &&
                    declarationDefinitelyActive(param, active)
            ) {
                addLocalDeclaration(db, file, param, names, found)
            }
        }
        for (child in node.children()) {
            visit(child)
        }
    }
    visit(root)
    found.toArray()
}

func checkItemRedeclarations(
    db: AnalysisDatabase,
    file: ItemFile,
    items: Array<Item>,
    previous: ArrayList<(ItemFile, Item)>,
    root: CjSyntaxNode,
    found: ArrayList<Diagnostic>,
    enumName!: ?String = None
): Unit {
    let (_, ids) = syntaxOf(db, file) ?? return;
    for (item in items) {
        // Opaque macro input and common/specific pairing do not establish two declarations.
        if (
            !item.macros.isEmpty() || item.has(Modifier.Common) || item.has(Modifier.Specific) ||
                !itemDefinitelyActive(db, file, item)
        ) {
            continue
        }
        let node = ids.node(item.id, root) ?? continue
        if (
            isInitializer(item) &&
                previous
                    .any {
                        entry =>
                        let other = entry[1]
                        isInitializer(other) &&
                            item.has(Modifier.Static) == other.has(Modifier.Static) &&
                            sameOverload(
                                db,
                                DefId(db, file, item.id),
                                DefId(db, entry[0], other.id)
                            )
                    }
        ) {
            let range =
                InitDecl
                    .cast(node)
                    .flatMap { decl => decl.initToken() }
                    .map { token => token.textRange } ??
                    declNameRange(node)
            found.add(
                Diagnostic(range, Severity.Error, "constructor 'init' has overload conflicts")
            )
        }
        let names = bindingNames(node)
        let inPattern = HashSet<String>()
        for (name in names) {
            let text = name.text()
            var message: ?String = None
            if (!inPattern.add(text) && item.kind != ItemKind.PrimaryInit) {
                message = "redefinition of declaration '${text}'"
            }
            for ((otherFile, other) in previous) {
                let otherNames =
                    if (other.kind == ItemKind.PrimaryInit) {
                        let (otherRoot, otherIds) = syntaxOf(db, otherFile) ?? continue
                        let otherNode = otherIds.node(other.id, otherRoot) ?? continue
                        bindingNames(otherNode).map { one => one.text() }
                    } else {
                        other.names
                    }
                if (!otherNames.contains(text)) {
                    continue
                }
                if (
                    !other.macros.isEmpty() || other.has(Modifier.Common) ||
                        other.has(Modifier.Specific) ||
                        !itemDefinitelyActive(db, otherFile, other)
                ) {
                    continue
                }
                if (
                    otherFile != file && (item.has(Modifier.Private) || other.has(Modifier.Private))
                ) {
                    continue
                }
                // Macro overloads have separate arity/redefinition rules in cjc.
                if (item.kind == ItemKind.Macro && other.kind == ItemKind.Macro) {
                    continue
                }
                if (item.kind == ItemKind.Func && other.kind == ItemKind.Func) {
                    if (item.has(Modifier.Static) != other.has(Modifier.Static)) {
                        message = "overloaded functions '${text}' cannot mix static and non-static"
                    } else if (
                        sameOverload(db, DefId(db, file, item.id), DefId(db, otherFile, other.id))
                    ) {
                        message = "function '${text}' has overload conflicts"
                    }
                } else if (
                    let Some(owner) <- enumName && item.kind == ItemKind.EnumCtor &&
                        other.kind == ItemKind.EnumCtor
                ) {
                    // Enum constructors overload by arity, never by the types at one arity.
                    if (
                        signatureTypes(db, DefId(db, file, item.id)).params.size ==
                            signatureTypes(db, DefId(db, otherFile, other.id)).params.size
                    ) {
                        message = "'${text}' is already exist in enum '${owner}'"
                    }
                } else {
                    message = "redefinition of declaration '${text}'"
                }
            }
            if (let Some(message) <- message) {
                found.add(Diagnostic(name.syntax.textRange, Severity.Error, message))
            }
        }
        previous.add((file, item))
        checkItemRedeclarations(
            db,
            file,
            item.members,
            ArrayList<(ItemFile, Item)>(),
            root,
            found,
            enumName: if (item.kind == ItemKind.Enum) { item.names.get(0) } else { None }
        )
    }
}

func sameOverload(db: AnalysisDatabase, left: DefId, right: DefId): Bool {
    let a = signatureTypes(db, left)
    let b = signatureTypes(db, right)
    // Different generic arities and variadic signatures need the compiler's overlap relation.
    if (a.generics.size != b.generics.size || a.isCVariadic || b.isCVariadic) {
        return false
    }
    let args =
        Array(a.generics.size) { index => Ty(db, ParamTy(GenericOwner.Declaration(left), index)) }
    let normalized = b.params.map { ty => substitute(db, ty, right, args) }
    a.params == normalized && a.params.all { ty => declarationTypeKnown(db, ty) }
}

func declarationTypeKnown(db: AnalysisDatabase, ty: Ty): Bool {
    match (ty.kind(db)) {
        case PrimTy(_) | ParamTy(_, _) => true
        case DeclTy(_, args) => args.all { arg => declarationTypeKnown(db, arg) }
        case BuiltInTy(_, args) => args.all { arg => declarationTypeKnown(db, arg) }
        case TupleTy(args) => args.all { arg => declarationTypeKnown(db, arg) }
        case FuncTy(args, ret, _) =>
            args.all { arg => declarationTypeKnown(db, arg) } && declarationTypeKnown(db, ret)
        case VArrayTy(element, _) => declarationTypeKnown(db, element)
        case _ => false
    }
}

func isInitializer(item: Item): Bool {
    item.kind == ItemKind.Init || item.kind == ItemKind.PrimaryInit
}

func bindingNames(node: CjSyntaxNode): Array<Name> {
    if (node.kind == SyntaxKind.PrimaryInitDecl) {
        let names = ArrayList<Name>()
        for (list in node.children() where list.kind == SyntaxKind.ParamList) {
            for (child in list.children()) {
                let param = Param.cast(child) ?? continue
                // The member projection of conditional parameters needs its own active scope.
                if (conditionOf(child).isSome()) {
                    continue
                }
                if (param.letToken().isSome() || param.varToken().isSome()) {
                    if (let Some(name) <- param.name()) {
                        names.add(name)
                    }
                }
            }
        }
        return names.toArray()
    }
    if (let Some(decl) <- VarDecl.cast(node) && let Some(pattern) <- decl.pattern()) {
        let found = ArrayList<Name>()
        func collect(pattern: Pattern): Unit {
            match (pattern) {
                case Pattern.AsBindPat(it) =>
                    if (let Some(name) <- it.name()) {
                        found.add(name)
                    }
                case Pattern.AsTypePat(it) =>
                    if (let Some(name) <- it.name()) {
                        found.add(name)
                    }
                case Pattern.AsTuplePat(it) =>
                    for (inner in it.patterns()) {
                        collect(inner)
                    }
                case Pattern.AsEnumPat(it) =>
                    for (inner in it.patterns()) {
                        collect(inner)
                    }
                case _ => ()
            }
        }
        collect(pattern)
        return found.toArray()
    }
    AnyHasName.cast(node).flatMap { decl => decl.name() }.map { name => [name] } ?? []
}

func addLocalDeclaration(
    db: AnalysisDatabase,
    file: ItemFile,
    node: CjSyntaxNode,
    names: HashMap<String, Array<CjSyntaxNode>>,
    found: ArrayList<Diagnostic>,
    report!: Bool = true
): Unit {
    if (
        ![
            SyntaxKind.VarDecl,
            SyntaxKind.FuncDecl,
            SyntaxKind.Param,
            SyntaxKind.LambdaParam
        ].contains(node.kind)
    ) {
        return
    }
    for (name in bindingNames(node)) {
        let text = name.text()
        let previous = names.get(text) ?? []
        let conflict =
            previous
                .any {
                    other =>
                    if (node.kind == SyntaxKind.FuncDecl && other.kind == SyntaxKind.FuncDecl) {
                        let a = localOverloadParams(db, file, node)
                        let b = localOverloadParams(db, file, other)
                        a.isSome() && a == b
                    } else {
                        true
                    }
                }
        if (report && conflict) {
            let message =
                if (node.kind == SyntaxKind.FuncDecl &&
                    previous.all { other => other.kind == SyntaxKind.FuncDecl }) {
                    "function '${text}' has overload conflicts"
                } else {
                    "redefinition of declaration '${text}'"
                }
            found.add(Diagnostic(name.syntax.textRange, Severity.Error, message))
        }
        names[text] = previous.concat([node])
    }
}

func localOverloadParams(db: AnalysisDatabase, file: ItemFile, node: CjSyntaxNode): ?Array<Ty> {
    let function = FuncDecl.cast(node) ?? return None
    if (function.typeParamList().isSome()) {
        return None
    }
    let name = function.name() ?? return None
    let (_, ids) = syntaxOf(db, file) ?? return None
    let owner =
        node.ancestors() |> filterMap { ancestor: CjSyntaxNode => ids.idAround(ancestor) } |> first
    let def = DefId(db, file, owner ?? return None)
    let local =
        bodyWithSourceMap(db, def).sourceMap.localAt(SyntaxNodePtr(name.syntax)) ?? return None
    let ty = inferBody(db, def)[local] ?? return None
    match (ty.kind(db)) {
        case FuncTy(params, _, _) where params.all { param => declarationTypeKnown(db, param) } =>
            params
        case _ => None
    }
}

// Unknown cfg retains alternatives for lookup, but cannot prove two declarations coexist.
func declarationDefinitelyActive(node: CjSyntaxNode, active: ActiveFilter): Bool {
    let condition = conditionOf(node) ?? return active.isActive(node)
    condition.evaluate(active.cfg()) == Some(true)
}

func itemDefinitelyActive(db: AnalysisDatabase, file: ItemFile, item: Item): Bool {
    let source = scopeFileOf(db, file) ?? return false
    let (root, ids) = syntaxOf(db, file) ?? return false
    let node = ids.node(item.id, root) ?? return false
    let active = ActiveFilter.of(db, source)
    // Item summaries flatten foreign blocks, whose @When still guards every declaration in them.
    node.ancestors().all { ancestor => declarationDefinitelyActive(ancestor, active) }
}
