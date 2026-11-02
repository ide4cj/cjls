package loupe

import std.collection.*
import calca.*
import calca.macros.*
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.{
    AnyHasAnnotations,
    AnyHasModifiers,
    AnyHasName,
    Annotation,
    EnumCtor,
    FuncDecl,
    MacroExpandDecl,
    PropDecl,
    RefExpr
}
import ginkgo.{SyntaxElement, TextRange}
import loupe.db.{AnalysisDatabase, MacroSeverity, SourceFile}
import loupe.hir.*
import loupe.syntax.parse

/**
 * Declaration validation, including resolved extension heads. Compiler target checks live in
 * Sema/FFI/CFFICheck.cpp and Sema/DeclAttributeChecker.cpp; keep their point ranges intact.
 */
@CalcaTracked
func declarationDiagnostics(db: AnalysisDatabase, file: SourceFile): Array<Diagnostic> {
    let root = parse(db, file).syntaxNode()
    let read = readServerCallsOf(db, file)
    let ids = itemIdMap(db, file)
    let replaced =
        read.iterator() |>
            filterMap {
                call: MacroCallId =>
                ids.node(call.item(db), root).map { node => node.textRange }
            } |>
            collectArray
    let found =
        ArrayList<Diagnostic>(
            declarationDiagnosticsInTree(
                db,
                ItemFile.Source(file),
                root,
                ActiveFilter.of(db, file),
                replaced
            )
        )
    for (call in read) {
        if (
            !macroRequests(db, file)
                .iterator()
                .any { request => request.call == call && request.current }
        ) {
            continue
        }
        let (_, head) = macroCallHeadOf(db, call) ?? continue
        for (
            one in declarationDiagnosticsInTree(
                db,
                ItemFile.Expansion(call),
                expansionParse(db, call).syntaxNode(),
                ActiveFilter.of(db, file),
                []
            )
        ) {
            found
                .add(
                    Diagnostic(
                        sourceRangeOf(db, call, one.range) ?? head,
                        one.severity,
                        one.message
                    )
                )
        }
    }
    for (
        request in macroRequests(db, file) where request.current && request.call.inBody(db).isSome()
    ) {
        let call = request.call
        let item = ids.node(call.item(db), root) ?? continue
        if (
            replaced
                .iterator()
                .any {
                    range =>
                    range.start <= item.textRange.start && item.textRange.end <= range.end
                }
        ) {
            continue
        }
        let output = macroOutputOf(db, call) ?? continue
        if (
            output.expansion.isNone() ||
                output.diagnostics.any { one => one.severity == MacroSeverity.MacroError }
        ) {
            continue
        }
        let parsed = expansionParse(db, call)
        if (!parsed.errors.isEmpty() || bodyCallNodeOf(db, call).isNone()) {
            continue
        }
        let (_, head) = macroCallHeadOf(db, call) ?? continue
        for (
            one in declarationDiagnosticsInTree(
                db,
                ItemFile.Expansion(call),
                parsed.syntaxNode(),
                ActiveFilter.of(db, file),
                [],
                local: true
            )
        ) {
            found
                .add(
                    Diagnostic(
                        sourceRangeOf(db, call, one.range) ?? head,
                        one.severity,
                        one.message
                    )
                )
        }
    }
    found.toArray()
}

func declarationDiagnosticsInTree(
    db: AnalysisDatabase,
    file: ItemFile,
    root: CjSyntaxNode,
    active: ActiveFilter,
    replaced: Array<TextRange>,
    local!: Bool = false
): Array<Diagnostic> {
    let found = ArrayList<Diagnostic>()
    func visit(node: CjSyntaxNode, owner: ?CjSyntaxNode, local: Bool, isForeign: Bool): Unit {
        if (replaced.contains(node.textRange)) {
            return
        }
        if (
            node.kind == SyntaxKind.MainDecl &&
                hasRejectedNativeMainAnnotations(
                    AnyHasAnnotations
                        .cast(node)
                        .map { decl => decl.annotations() |> collectArray } ??
                        [],
                    found
                )
        ) {
            return
        }
        if (!active.isActive(node)) {
            return
        }
        if (let Some(call) <- MacroExpandDecl.cast(node)) {
            checkMainAnnotationWrapper(db, file, call, found)
            return
        }
        let inheritedForeign = isForeign || node.kind == SyntaxKind.ForeignBlock
        let declaration = AnyHasAnnotations.cast(node)
        if (let Some(decl) <- declaration) {
            for (annotation in decl.annotations()) {
                checkDeclarationAnnotation(node, annotation, owner, local, inheritedForeign, found)
            }
            checkDeclarationModifiers(node, owner, inheritedForeign, found)
            checkPropertyAccessors(node, active, found)
            if (node.kind == SyntaxKind.ExtendDecl) {
                checkExtendMutModifiers(db, file, node, found)
            }
        }
        let nextOwner = if (declarationKind(node).isSome()) { Some(node) } else { owner }
        let nextLocal = local || node.kind == SyntaxKind.Block || node.kind == SyntaxKind.LambdaExpr
        for (child in node.children()) {
            visit(child, nextOwner, nextLocal, inheritedForeign)
        }
    }
    visit(root, None, local, false)
    found.toArray()
}

/**
 * Reports parser-owned main annotation errors and returns whether later checks must stop.
 * ParseMainDecl runs before inactive declarations are removed; C target checks run later.
 */
func hasRejectedNativeMainAnnotations(
    annotations: Array<Annotation>,
    found: ArrayList<Diagnostic>
): Bool {
    let first = annotations.get(0) ?? return false
    let allowed = ["When", "C", "OverflowThrowing", "OverflowWrapping", "OverflowSaturating"]
    let hasRejected =
        annotations.any { annotation => !allowed.contains(annotation.nameRef()?.text() ?? "") }
    if (!hasRejected) {
        return false
    }
    for (annotation in annotations where annotation.nameRef()?.text() == Some("Deprecated")) {
        found
            .add(
                Diagnostic(
                    annotation.syntax.textRange,
                    Severity.Error,
                    "main can not be target of @Deprecated"
                )
            )
    }
    // cjc points at annos[0], even if a later annotation is the rejected one; one error occupies that span.
    if (first.nameRef()?.text() != Some("Deprecated")) {
        let name = first.nameRef()?.text() ?? return true
        found
            .add(
                Diagnostic(
                    first.syntax.textRange,
                    Severity.Error,
                    "unexpected annotation '@${name}' on main"
                )
            )
    }
    true
}

/**
 * The parser rejects the first non-conditional annotation on main before resolving its name.
 */
func checkMainAnnotationWrapper(
    db: AnalysisDatabase,
    file: ItemFile,
    call: MacroExpandDecl,
    found: ArrayList<Diagnostic>
): Unit {
    let path = call.nameRefs() |> map { name => name.text() } |> collectArray
    if (let Some(source) <- scopeFileOf(db, file) && let Some(pkg) <- packageOfFile(db, source)) {
        // A real macro owns its input until a successful output is read, including a main declaration.
        if (
            resolveMacroPath(db, pkg, source, path).get(path.size - 1) != Some(Resolution.NotFound)
        ) {
            return
        }
    }
    var target = call.decl()?.syntax ?? return;
    while (let Some(inner) <- MacroExpandDecl.cast(target).flatMap { nested => nested.decl() }) {
        target = inner.syntax
    }
    if (target.kind != SyntaxKind.MainDecl) {
        return
    }
    for (annotation in call.annotations() where annotation.nameRef()?.text() != Some("When")) {
        let name = annotation.nameRef()?.text() ?? return;
        found
            .add(
                Diagnostic(
                    annotation.syntax.textRange,
                    Severity.Error,
                    "unexpected annotation '@${name}' on main"
                )
            )
        return
    }
    let name = String.join(path, delimiter: ".")
    let start = call.atToken()?.textRange.start ?? call.atBangToken()?.textRange.start ?? return
    let headEnd = call.nameRefs().fold(start) { _, name => name.syntax.textRange.end }
    let end = call.macroAttr()?.syntax.textRange.end ?? headEnd
    found
        .add(
            Diagnostic(
                TextRange(start, end),
                Severity.Error,
                "unexpected annotation '@${name}' on main"
            )
        )
}

func declarationHas(node: CjSyntaxNode, modifier: SyntaxKind): Bool {
    let modifiers = AnyHasModifiers.cast(node).flatMap { decl => decl.modifiers() } ?? return false
    modifiers
        .syntax
        .childrenWithTokens()
        .any {
            element =>
            match (element) {
                case SyntaxElement.Token(token) => token.kind == modifier
                case _ => false
            }
        }
}

func declarationKind(node: CjSyntaxNode): ?String {
    match (node.kind) {
        case SyntaxKind.ClassDecl => "class"
        case SyntaxKind.StructDecl => "struct"
        case SyntaxKind.InterfaceDecl => "interface"
        case SyntaxKind.EnumDecl => "enum"
        case SyntaxKind.ExtendDecl => "extend"
        case SyntaxKind.VarDecl => "variable"
        case SyntaxKind.Param => "parameter"
        case SyntaxKind.EnumCtor =>
            if (EnumCtor.cast(node)?.lParenToken().isSome() ?? false) {
                "function"
            } else {
                "variable"
            }
        case SyntaxKind.MainDecl => "main"
        case SyntaxKind.PropDecl => "property"
        case SyntaxKind.TypeAliasDecl => "type alias"
        case SyntaxKind.FuncDecl |
            SyntaxKind.InitDecl |
            SyntaxKind.PrimaryInitDecl |
            SyntaxKind.FinalizerDecl => "function"
        case _ => None
    }
}

func checkDeclarationAnnotation(
    node: CjSyntaxNode,
    annotation: Annotation,
    owner: ?CjSyntaxNode,
    local: Bool,
    inheritedForeign: Bool,
    found: ArrayList<Diagnostic>
): Unit {
    let name = annotation.nameRef()?.text() ?? return
    let kind = declarationKind(node) ?? return
    let function = kind == "function"
    let isForeign = inheritedForeign || declarationHas(node, SyntaxKind.ForeignKw)
    let nested = local || owner.isSome()
    let point = annotation.atToken()?.textRange ?? return
    let whole = annotation.syntax.textRange
    let args = annotation.annotationArgList().map { list => list.args() |> collectArray } ?? []
    if (["Frozen", "C", "FastNative"].contains(name) && !args.isEmpty()) {
        let start = args[0].syntax.textRange.start
        found
            .add(
                Diagnostic(
                    TextRange(start, start + 1),
                    Severity.Error,
                    "'@${name}' should have no arg"
                )
            )
    }
    if (name == "C") {
        let generic = FuncDecl.cast(node).flatMap { decl => decl.typeParamList() }
        if (let Some(token) <- generic.flatMap { list => list.ltToken() }) {
            found
                .add(
                    Diagnostic(token.textRange, Severity.Error, "CFunc cannot have type parameters")
                )
        }
    }
    var range = point
    let message: ?String =
        match (name) {
            case "Frozen" =>
                if (!function && node.kind != SyntaxKind.PropDecl) {
                    "${kind} cannot be modified with '@Frozen'"
                } else if (function && local) {
                    "local function cannot be modified with '@Frozen'"
                } else {
                    None
                }
            case "C" =>
                if (!function && node.kind != SyntaxKind.StructDecl) {
                    "${kind} cannot be modified with '@C'"
                } else if (nested) {
                    range = whole
                    "'@C' can only be used in top-level scope"
                } else {
                    None
                }
            case "FastNative" =>
                if (!function || !isForeign) {
                    let prefix = if (function) { "non-foreign " } else { "" }
                    "${prefix}${kind} cannot be modified with '@FastNative'"
                } else if (nested) {
                    range = whole
                    "'@FastNative' can only be used in top-level scope"
                } else {
                    None
                }
            case "CallingConv" =>
                range = whole
                if (nested) {
                    "'@CallingConv' can only be used in top-level scope"
                } else if (!function || (!isForeign && !hasDeclarationAnnotation(node, "C"))) {
                    "only CFunc can use '@CallingConv'"
                } else if (args.size != 1) {
                    "'@CallingConv' should have one arg"
                } else if (
                    let Some(refExpr) <- args[0]
                        .expr()
                        .flatMap { expr => RefExpr.cast(expr.syntax) }
                ) {
                    let convention = refExpr.nameRef()?.text() ?? return;
                    if (convention == "CDECL") {
                        None
                    } else {
                        "'@CallingConv' have not supported '${convention}' yet"
                    }
                } else {
                    "'@CallingConv' arg should be right type"
                }
            case _ => None
        }
    if (let Some(text) <- message) {
        found.add(Diagnostic(range, Severity.Error, text))
    }
}

func hasDeclarationAnnotation(node: CjSyntaxNode, name: String): Bool {
    let decl = AnyHasAnnotations.cast(node) ?? return false
    decl.annotations().any { annotation => annotation.nameRef()?.text() == Some(name) }
}

func checkDeclarationModifiers(
    node: CjSyntaxNode,
    owner: ?CjSyntaxNode,
    isForeign: Bool,
    found: ArrayList<Diagnostic>
): Unit {
    if (declarationModifierConflicts(node, owner, found)) {
        return
    }
    if (
        node.kind == SyntaxKind.ClassDecl && declarationHas(node, SyntaxKind.SealedKw) &&
            !declarationHas(node, SyntaxKind.AbstractKw)
    ) {
        found
            .add(
                Diagnostic(
                    declNameRange(node),
                    Severity.Error,
                    "non-abstract class cannot be modified by 'sealed'"
                )
            )
    }
    let function = FuncDecl.cast(node)
    if (
        let Some(funcDecl) <- function && funcDecl.typeParamList().isSome() &&
            declarationHas(node, SyntaxKind.OperatorKw)
    ) {
        // Diagnose(Node, ...) uses the declaration's begin, including its first modifier.
        found
            .add(
                Diagnostic(
                    declarationBegin(node),
                    Severity.Error,
                    "generic is not allowed in operator overload function"
                )
            )
    }
    let parent = owner ?? return;
    if (parent.kind != SyntaxKind.ClassDecl) {
        return
    }
    if (
        ["JavaMirror", "ObjCMirror", "ObjCImpl"]
            .iterator()
            .any { name => hasDeclarationAnnotation(parent, name) }
    ) {
        return
    }
    if (
        node.kind == SyntaxKind.FinalizerDecl &&
            (
                declarationHas(parent, SyntaxKind.OpenKw) ||
                    declarationHas(parent, SyntaxKind.AbstractKw) ||
                    declarationHas(parent, SyntaxKind.SealedKw)
            )
    ) {
        let name = AnyHasName.cast(parent)?.name()?.text() ?? return
        let modifier =
            if (declarationHas(parent, SyntaxKind.OpenKw) ||
                declarationHas(parent, SyntaxKind.SealedKw)) {
                "open"
            } else {
                "abstract"
            }
        found
            .add(
                Diagnostic(
                    declarationBegin(node),
                    Severity.Error,
                    "finalizer is forbidden in class '${name}' that is ${modifier}"
                )
            )
    }
    if (node.kind != SyntaxKind.FuncDecl && node.kind != SyntaxKind.PropDecl) {
        return
    }
    let abstractClass = declarationHas(parent, SyntaxKind.AbstractKw)
    let inheritable =
        abstractClass || declarationHas(parent, SyntaxKind.OpenKw) ||
            declarationHas(parent, SyntaxKind.SealedKw)
    let hasBody =
        if (let Some(funcDecl) <- function) {
            funcDecl.block().isSome()
        } else {
            PropDecl.cast(node)?.propBody().isSome() ?? false
        }
    let abstractMember =
        declarationHas(node, SyntaxKind.AbstractKw) ||
            (
                !hasBody && !isForeign && !declarationHas(node, SyntaxKind.CommonKw) &&
                    !declarationHas(node, SyntaxKind.SpecificKw) &&
                    !declarationHas(parent, SyntaxKind.CommonKw) &&
                    !declarationHas(parent, SyntaxKind.SpecificKw)
            )
    let kind = if (function.isSome()) { "function" } else { "property" }
    let multiplatform =
        declarationHas(parent, SyntaxKind.CommonKw) || declarationHas(parent, SyntaxKind.SpecificKw)
    if (multiplatform && declarationHas(node, SyntaxKind.AbstractKw) && hasBody) {
        found.add(Diagnostic(node.textRange, Severity.Error, "abstract ${kind} can not have body"))
    }
    if (
        multiplatform && abstractClass && !hasBody &&
            !declarationHas(node, SyntaxKind.AbstractKw) &&
            !declarationHas(node, SyntaxKind.CommonKw) &&
            !declarationHas(node, SyntaxKind.SpecificKw)
    ) {
        let modifier =
            if (declarationHas(parent, SyntaxKind.CommonKw)) { "common" } else { "specific" }
        found
            .add(
                Diagnostic(
                    declNameRange(node),
                    Severity.Error,
                    "'${modifier}' abstract class ${kind} must have explicit '${modifier}' or 'abstract' modifier"
                )
            )
    }
    if (
        abstractMember && (!abstractClass || declarationHas(node, SyntaxKind.StaticKw)) &&
            !declarationHas(parent, SyntaxKind.ForeignKw)
    ) {
        let name = AnyHasName.cast(node)?.name()?.text() ?? return;
        found
            .add(
                Diagnostic(
                    declarationBegin(node),
                    Severity.Error,
                    "${kind} '${name}' can not be abstract"
                )
            )
    }
    let visibility =
        declarationHas(node, SyntaxKind.PublicKw) || declarationHas(node, SyntaxKind.ProtectedKw)
    if (!visibility && abstractMember && abstractClass) {
        found
            .add(
                Diagnostic(
                    declNameRange(node),
                    Severity.Error,
                    "the visibility of an 'abstract' ${kind} must be 'public' or 'protected'"
                )
            )
    }
    if (!visibility && !abstractMember && inheritable && declarationHas(node, SyntaxKind.OpenKw)) {
        found
            .add(
                Diagnostic(
                    declNameRange(node),
                    Severity.Error,
                    "the visibility of an 'open' ${kind} must be 'public' or 'protected'"
                )
            )
    }
}

func declarationBegin(node: CjSyntaxNode): TextRange {
    let start = codeRange(node).start
    TextRange(start, start + 1)
}

/**
 * The conflict pairs from Parse/ParserModifierRules.cpp. The later modifier owns the range,
 * regardless of the order of the pair in the compiler's table.
 */
func declarationModifierConflicts(
    node: CjSyntaxNode,
    owner: ?CjSyntaxNode,
    found: ArrayList<Diagnostic>
): Bool {
    let modifiers = AnyHasModifiers.cast(node).flatMap { decl => decl.modifiers() } ?? return false
    let tokens =
        modifiers.syntax.childrenWithTokens() |>
            filterMap {
                element: SyntaxElement<SyntaxKind> =>
                match (element) {
                    case SyntaxElement.Token(token) where !token.kind.isTrivia() => Some(token)
                    case _ => None<CjSyntaxToken>
                }
            } |>
            collectArray
    let kind = declarationKind(node) ?? return false
    let pairs = ArrayList<(String, String)>()
    let access = ["public", "private", "internal", "protected"]
    for (i in 0..access.size) {
        for (j in i + 1..access.size) {
            pairs.add((access[i], access[j]))
        }
    }
    pairs.add(("common", "specific"))
    let parent = owner.map { one => one.kind }
    if (owner.isNone()) {
        if (["class", "interface", "struct", "enum", "variable", "function"].contains(kind)) {
            pairs.add(("private", "common"))
            pairs.add(("private", "specific"))
        }
        if (["class", "interface"].contains(kind)) {
            for (visibility in ["private", "internal", "protected"]) {
                pairs.add((visibility, "sealed"))
            }
        }
        if (["class", "interface", "variable", "function"].contains(kind)) {
            pairs.add(("public", "foreign"))
        }
        if (["variable", "function"].contains(kind)) {
            pairs.add(("const", "foreign"))
            pairs.add(("unsafe", "foreign"))
            pairs.add(("common", "foreign"))
        }
        if (kind == "variable") {
            pairs.add(("specific", "foreign"))
        }
        if (kind == "function") {
            for (visibility in ["private", "internal", "protected"]) {
                pairs.add((visibility, "foreign"))
            }
        }
    }
    let memberFunction = node.kind == SyntaxKind.FuncDecl
    let memberProperty = node.kind == SyntaxKind.PropDecl
    if (parent == Some(SyntaxKind.ClassDecl) && (memberFunction || memberProperty)) {
        for (modifier in ["static", "private", "internal", "redef"]) {
            pairs.add(("open", modifier))
        }
        if (memberFunction) {
            pairs.add(("const", "open"))
        }
    }
    if (
        (parent == Some(SyntaxKind.ClassDecl) || parent == Some(SyntaxKind.InterfaceDecl)) &&
            (memberFunction || memberProperty)
    ) {
        pairs.add(("static", "open"))
        pairs.add(("redef", "open"))
    }
    if (
        owner.isSome() && (memberFunction || memberProperty) &&
            parent != Some(SyntaxKind.ExtendDecl)
    ) {
        pairs.add(("override", "static"))
        pairs.add(("override", "redef"))
    }
    if (owner.isSome() && memberFunction) {
        pairs.add(("operator", "static"))
        if (parent != Some(SyntaxKind.ExtendDecl)) {
            pairs.add(("operator", "redef"))
        }
        if (parent == Some(SyntaxKind.StructDecl)) {
            pairs.add(("const", "mut"))
        }
        if (
            parent == Some(SyntaxKind.StructDecl) || parent == Some(SyntaxKind.InterfaceDecl) ||
                parent == Some(SyntaxKind.ExtendDecl)
        ) {
            pairs.add(("mut", "static"))
        }
    }
    if (node.kind == SyntaxKind.InitDecl || node.kind == SyntaxKind.PrimaryInitDecl) {
        for (visibility in access) {
            pairs.add(("static", visibility))
        }
    }
    var invalid = false
    for (i in 0..tokens.size) {
        let current = tokens[i].text()
        for (j in 0..i) {
            let earlier = tokens[j].text()
            let asymmetricAllowed =
                (
                    owner.isNone() && kind == "function" && current == "private" &&
                        earlier == "specific"
                ) ||
                    (
                        (
                            parent == Some(SyntaxKind.StructDecl) ||
                                parent == Some(SyntaxKind.EnumDecl)
                        ) &&
                            memberFunction &&
                            current == "static" &&
                            earlier == "override"
                    ) ||
                    (
                        parent != Some(SyntaxKind.ClassDecl) && memberFunction &&
                            current == "operator" &&
                            earlier == "redef"
                    )
            if (
                !asymmetricAllowed &&
                    pairs
                        .iterator()
                        .any { pair => pair == (current, earlier) || pair == (earlier, current) }
            ) {
                found
                    .add(
                        Diagnostic(
                            tokens[i].textRange,
                            Severity.Error,
                            "'${current}' and '${earlier}' modifiers conflict on ${kind} declaration"
                        )
                    )
                invalid = true
            }
        }
    }
    invalid
}

/** Check only resolved nominal or primitive heads; unavailable types cannot establish a bad modifier. */
func checkExtendMutModifiers(
    db: AnalysisDatabase,
    file: ItemFile,
    node: CjSyntaxNode,
    found: ArrayList<Diagnostic>
): Unit {
    let (_, ids) = syntaxOf(db, file) ?? return
    let id = ids.idAround(node) ?? return
    let ty = signatureTypes(db, DefId(db, file, id)).ty ?? return
    let name: String =
        match (ty.kind(db)) {
            case DeclTy(def, _) where def.item(db).kind != ItemKind.Struct =>
                (itemOf(db, def) ?? return).names.get(0) ?? return;
            case PrimTy(name) => name
            case _ => return
        }
    let primitive = if (let PrimTy(_) <- ty.kind(db)) { true } else { false }
    for (child in node.children()) {
        // Only an extend's immediate members inherit its target; a local function has its own context.
        if (child.kind != SyntaxKind.DeclBody) {
            continue
        }
        for (
            member in child.children() where member.kind == SyntaxKind.FuncDecl ||
                (primitive && member.kind == SyntaxKind.PropDecl)
        ) {
            let modifiers =
                AnyHasModifiers.cast(member).flatMap { decl => decl.modifiers() } ?? continue
            for (element in modifiers.syntax.childrenWithTokens()) {
                if (let SyntaxElement.Token(token) <- element && token.kind == SyntaxKind.MutKw) {
                    found
                        .add(
                            Diagnostic(
                                token.textRange,
                                Severity.Error,
                                "'mut' modifier is illegal in extend body of '${name}'"
                            )
                        )
                }
            }
        }
    }
}
