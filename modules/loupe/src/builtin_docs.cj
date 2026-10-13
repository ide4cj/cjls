package loupe

/**
 * The Cangjie docs, at the commit the texts below were written from, which `.corpora/cangjie_docs` is fetched at
 * (`tests/corpora/fetch.py`): the language guide in English.
 */
public const CANGJIE_DOCS_COMMIT = "fc561c3ff9127a92c53e120426bdc914317cea6e"

let CANGJIE_DOCS = "https://github.com/cangjielanguage/cangjie_docs/blob/${CANGJIE_DOCS_COMMIT}/docs/dev-guide/source_en/"

/**
 * What the language builds in and no source declares — a type that is a keyword, a type of the compiler's own, an
 * annotation, a macro of the compiler's — told in our words after the Cangjie docs, which are CC BY 4.0, and the
 * section of them it comes from (D109).
 */
public struct BuiltinDoc {
    public BuiltinDoc(
        /**
         * Its name as code writes it, without the `@` of an annotation.
         */
        public let name: String,
        /**
         * How it is written, as a hover shows it: `type Int64`, `@When[condition]`.
         */
        public let code: String,
        /**
         * What it is, as Markdown.
         */
        public let summary: String,
        /**
         * The page of the guide, relative to `source_en`, and the anchor of its section.
         */
        public let page: String,
        public let anchor: String
    ) {}

    /**
     * Where in the Cangjie docs it is told.
     */
    public prop link: String {
        get() {
            "${CANGJIE_DOCS}${page}#${anchor}"
        }
    }
}

let INTEGERS = "basic_data_type/integer.md"
let FLOATS = "basic_data_type/float.md"
let FFI = "FFI/cangjie-c.md"
let FLAGS = "Macro/builtin_compilation_flags.md"
let ANNOTATIONS = "reflect_and_annotation/anno.md"
let JAVA = "multiplatform/cangjie-android-Java.md"
let OBJC = "multiplatform/cangjie-ios-objc.md"

func integer(name: String, what: String, range: String, suffix: String): BuiltinDoc {
    let literal = if (suffix.isEmpty()) {
        "A literal has no suffix of this type: it takes it from where it is used."
    } else {
        "A literal of this type is suffixed `${suffix}`: `1${suffix}`."
    }
    BuiltinDoc(name, "type ${name}", "${what}, ${range}. ${literal}", INTEGERS, "integer-types")
}

func float(name: String, what: String, digits: String, suffix: String): BuiltinDoc {
    BuiltinDoc(name, "type ${name}", "${what} (IEEE 754), about ${digits} significant decimal digits. " +
        "A literal of this type is suffixed `${suffix}`: `1.5${suffix}`.", FLOATS, "floating-point-types")
}

/**
 * The types the language builds in: those the grammar has as keywords, and those of the compiler's own that only
 * `std.core`'s `.cjo` declares (`ItemKind.BuiltIn`).
 */
let BUILTIN_TYPE_DOCS: Array<BuiltinDoc> = [
    integer("Int8", "An 8-bit signed integer", "from -128 to 127", "i8"),
    integer("Int16", "A 16-bit signed integer", "from -32,768 to 32,767", "i16"),
    integer("Int32", "A 32-bit signed integer", "from -2^31 to 2^31-1", "i32"),
    BuiltinDoc("Int64", "type Int64",
        "A 64-bit signed integer, from -2^63 to 2^63-1: the integer type preferred, which an integer literal is " +
            "where nothing gives it another. A literal of this type is suffixed `i64`: `1i64`.", INTEGERS,
        "integer-types"),
    integer("IntNative", "A signed integer", "as wide as the platform's word", ""),
    integer("UInt8", "An 8-bit unsigned integer, a byte", "from 0 to 255; `b'x'` is a byte literal", "u8"),
    integer("UInt16", "A 16-bit unsigned integer", "from 0 to 65,535", "u16"),
    integer("UInt32", "A 32-bit unsigned integer", "from 0 to 2^32-1", "u32"),
    integer("UInt64", "A 64-bit unsigned integer", "from 0 to 2^64-1", "u64"),
    integer("UIntNative", "An unsigned integer", "as wide as the platform's word", ""),
    float("Float16", "A 16-bit floating-point number, binary16", "3", "f16"),
    float("Float32", "A 32-bit floating-point number, binary32", "6", "f32"),
    float("Float64", "A 64-bit floating-point number, binary64", "15", "f64"),
    BuiltinDoc("Bool", "type Bool", "A truth value, `true` or `false`, of the operators `!`, `&&` and `||`.",
        "basic_data_type/bool.md", "boolean-type"),
    BuiltinDoc("Rune", "type Rune",
        "A Unicode character, any of them. Its literals: `r'a'`, `r\"b\"`, an escape `r'\\n'`, a code point " +
            "`r'\\u{4f60}'`.", "basic_data_type/characters.md", "character-type"),
    BuiltinDoc("Unit", "type Unit",
        "The type of what is evaluated for its effect alone: an assignment, a loop, a function returning nothing " +
            "else. Its one value is `()`; it has `==` and `!=` only.", "basic_data_type/unit.md", "the-unit-type"),
    BuiltinDoc("Nothing", "type Nothing",
        "The type of no value, a subtype of every type: the type of `break`, `continue`, `return` and `throw`. " +
            "The compiler does not take it written as a type.", "basic_data_type/nothing.md", "the-nothing-type"),
    BuiltinDoc("VArray", "type VArray<T, $N>",
        "An array that is a value, of `$N` elements of type `T`, its length an `Int64` literal part of its type: " +
            "`VArray<Int64, $3>`. Made by `VArray<T, $N>({i => ...})` or `VArray<T, $N>(repeat: v)`; it has `[]` and " +
            "`size`. An element is no reference type, enum, lambda (but a `CFunc`) or generic type.",
        "basic_data_type/array.md", "varray"),
    BuiltinDoc("CPointer", "type CPointer<T>",
        "A C pointer to a `T` that is a `CType`: read, written, moved by arithmetic, compared to null and turned " +
            "into an integer; reading, writing and arithmetic in `unsafe` only.", FFI, "pointers"),
    BuiltinDoc("CString", "type CString",
        "A C string, `char *`: made by `LibC.mallocCString`, freed by `LibC.free`; `size()`, `isNull()`, " +
            "`startsWith`, `toString()` and the like read it.", FFI, "strings"),
    BuiltinDoc("CFunc", "type CFunc<F>",
        "A function C can call: a `foreign` or an `@C` function, or a lambda of this type, which captures " +
            "nothing; called in `unsafe` only.", FFI, "cfunc")
]

/**
 * The annotations the compiler knows (`BuiltinAnnotationName` in `cjsyntax`) that the Cangjie docs tell of; not
 * `@Intrinsic`, `@ConstSafe` and `@NonProduct`, std's own.
 */
let BUILTIN_ANNOTATION_DOCS: Array<BuiltinDoc> = [
    BuiltinDoc("Frozen", "@Frozen",
        "The function or property will not change in later versions: neither its signature nor its body, so the " +
            "same compiler with the same options builds the same code of it. On any function but a local one, and " +
            "on a property.", FLAGS, "frozen"),
    BuiltinDoc("When", "@When[condition]",
        "Conditional compilation: the import or declaration is compiled only where the condition holds, of " +
            "`os`, `arch`, `env`, `backend`, `cjc_version`, `debug`, `test` and the variables `--cfg` sets: " +
            "`@When[os == \"Linux\" && !debug]`.", "compile_and_build/conditional_compilation.md",
        "conditional-compilation-for-imports-and-declarations"),
    BuiltinDoc("FastNative", "@FastNative",
        "A faster call of a `foreign` function, for a C function that returns soon: one that neither blocks nor " +
            "loops long, nor calls Cangjie.", FLAGS, "fastnative"),
    BuiltinDoc("Attribute", "@Attribute[name]",
        "Attributes of the declaration that macros read: `std.ast`'s `getAttrs()` and `hasAttr(name)`.", FLAGS,
        "attribute"),
    BuiltinDoc("Deprecated", "@Deprecated[message, since: version, strict: Bool]",
        "The declaration is deprecated: still there, to be removed or changed. A use warns (`-Woff deprecated`), " +
            "or with `strict: true` is an error.", FLAGS, "deprecated"),
    BuiltinDoc("OverflowThrowing", "@OverflowThrowing",
        "An integer operation or conversion in the function that overflows throws an exception, and " +
            "one the compiler finds is an error: the default.", ANNOTATIONS,
        "built-in-compilation-markers-for-integer-overflow-handling-strategies"),
    BuiltinDoc("OverflowWrapping", "@OverflowWrapping",
        "An integer operation or conversion in the function that overflows wraps around: the bits beyond the " +
            "type are dropped.", ANNOTATIONS, "built-in-compilation-markers-for-integer-overflow-handling-strategies"),
    BuiltinDoc("OverflowSaturating", "@OverflowSaturating",
        "An integer operation or conversion in the function that overflows gives the type's minimum or maximum.",
        ANNOTATIONS, "built-in-compilation-markers-for-integer-overflow-handling-strategies"),
    BuiltinDoc("EnsurePreparedToMock", "@EnsurePreparedToMock",
        "On a lambda whose last expression uses a declaration of a package compiled for mocking: prepares it to " +
            "be mocked. Only with `--test` and `--mock`; for test frameworks, rarely written by hand.", ANNOTATIONS,
        "test-framework-built-in-compilation-markers"),
    BuiltinDoc("Annotation", "@Annotation[target: [AnnotationKind...]]",
        "The class is an annotation of your own, which reflection reads (`TypeInfo.of(x).findAnnotation<T>()`): " +
            "a class neither `abstract`, `open` nor `sealed`, with a `const init`.", ANNOTATIONS, "custom-annotations"),
    BuiltinDoc("C", "@C",
        "A function C calls, a `CFunc` called in `unsafe`; or a struct laid out as C's, of `CType` members, " +
            "itself a `CType`.", FFI, "calling-c-functions-from-cangjie"),
    BuiltinDoc("CallingConv", "@CallingConv[CDECL]",
        "The calling convention of a `foreign` block or function or a `CFunc`: `CDECL`, clang's C default, the " +
            "only one, and the convention where none is written.", FFI, "calling-conventions"),
    BuiltinDoc("JavaMirror", "@JavaMirror[\"java.lang.Name\"]",
        "A mirror of the Java type named: its members declared without bodies, for Cangjie to use Java's.", JAVA,
        "mirroring-java-types-to-cangjie"),
    BuiltinDoc("JavaImpl", "@JavaImpl",
        "A class of Cangjie that Java uses, inheriting mirrored types; the compiler writes its Java wrapper.", JAVA,
        "interop-classes"),
    BuiltinDoc("JavaHasDefault", "@JavaHasDefault",
        "A mirrored method of an interface that has a body in Java, `default` there.", JAVA,
        "mirroring-java-types-to-cangjie"),
    BuiltinDoc("ObjCMirror", "@ObjCMirror[\"Name\"]",
        "A mirror of an Objective-C class or protocol, named as in Objective-C if the mirror's name differs.", OBJC,
        "mirroring-objective-c-types-to-cangjie"),
    BuiltinDoc("ObjCImpl", "@ObjCImpl",
        "A class of Cangjie that Objective-C uses, through a wrapper class generated for it.", OBJC,
        "interop-classes"),
    BuiltinDoc("ObjCInit", "@ObjCInit",
        "A static function mirroring an Objective-C `init` method that cannot be a constructor.", OBJC, "classes"),
    BuiltinDoc("ObjCOptional", "@ObjCOptional",
        "A mirror of an optional method of a protocol: a call of it throws if the receiver does not implement it.",
        OBJC, "protocols"),
    BuiltinDoc("ForeignName", "@ForeignName[\"name\"]",
        "The member's name on the other side, Java's or an Objective-C selector, where it is not the mirror's.",
        OBJC, "names"),
    BuiltinDoc("ForeignGetterName", "@ForeignGetterName[\"name\"]",
        "The name of a mirrored Objective-C property's getter, where it is not the default.", OBJC,
        "classes-and-protocols"),
    BuiltinDoc("ForeignSetterName", "@ForeignSetterName[\"name\"]",
        "The name of a mirrored Objective-C property's setter, where it is not the default.", OBJC,
        "classes-and-protocols")
]

/**
 * The macros of the compiler's own, which no package declares.
 */
let BUILTIN_MACRO_DOCS: Array<BuiltinDoc> = [
    BuiltinDoc("sourcePackage", "@sourcePackage(): String",
        "The package of the file it is written in, as a `String` literal.", FLAGS, "source-location"),
    BuiltinDoc("sourceFile", "@sourceFile(): String", "The name of the file it is written in, as a `String` literal.",
        FLAGS, "source-location"),
    BuiltinDoc("sourceLine", "@sourceLine(): Int64", "The line it is written on, as an `Int64` literal.", FLAGS,
        "source-location")
]

func docNamed(docs: Array<BuiltinDoc>, name: String): ?BuiltinDoc {
    for (doc in docs where doc.name == name) {
        return doc
    }
    None
}

/**
 * The type the language builds in named `name`: a keyword's, or one of the compiler's own.
 */
public func builtinTypeDoc(name: String): ?BuiltinDoc {
    docNamed(BUILTIN_TYPE_DOCS, name)
}

/**
 * The annotation of the compiler's named `name`, without its `@`.
 */
public func builtinAnnotationDoc(name: String): ?BuiltinDoc {
    docNamed(BUILTIN_ANNOTATION_DOCS, name)
}

/**
 * The macro of the compiler's named `name`, without its `@`.
 */
public func builtinMacroDoc(name: String): ?BuiltinDoc {
    docNamed(BUILTIN_MACRO_DOCS, name)
}

/**
 * Every built-in told, for the tests holding them to the docs.
 */
func builtinDocs(): Array<BuiltinDoc> {
    BUILTIN_TYPE_DOCS.concat(BUILTIN_ANNOTATION_DOCS).concat(BUILTIN_MACRO_DOCS)
}
