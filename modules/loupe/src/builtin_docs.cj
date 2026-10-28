package loupe

import py_interop.*
import py_interop.internal_macros.*

/**
 * What the language builds in and no source declares — a type that is a keyword, a type of the compiler's own, an
 * annotation, a macro of the compiler's — told in our words (D109).
 */
@DerivePython
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
        public let summary: String
    ) {}
}

func integer(name: String, what: String, range: String, suffix: String): BuiltinDoc {
    let literal =
        if (suffix.isEmpty()) {
            "A literal has no suffix of this type: it takes it from where it is used."
        } else {
            "A literal of this type is suffixed `${suffix}`: `1${suffix}`."
        }
    BuiltinDoc(name, "type ${name}", "${what}, ${range}. ${literal}")
}

func float(name: String, what: String, digits: String, suffix: String): BuiltinDoc {
    BuiltinDoc(
        name,
        "type ${name}",
        "${what} (IEEE 754), about ${digits} significant decimal digits. " +
            "A literal of this type is suffixed `${suffix}`: `1.5${suffix}`."
    )
}

/**
 * The types the language builds in: those the grammar has as keywords, and those of the compiler's own that only
 * `std.core`'s `.cjo` declares (`ItemKind.BuiltIn`).
 */
let BUILTIN_TYPE_DOCS: Array<BuiltinDoc> =
    [
        integer("Int8", "An 8-bit signed integer", "from -128 to 127", "i8"),
        integer("Int16", "A 16-bit signed integer", "from -32,768 to 32,767", "i16"),
        integer("Int32", "A 32-bit signed integer", "from -2^31 to 2^31-1", "i32"),
        BuiltinDoc(
            "Int64",
            "type Int64",
            "A 64-bit signed integer, from -2^63 to 2^63-1: the integer type preferred, which an integer literal is " +
                "where nothing gives it another. A literal of this type is suffixed `i64`: `1i64`."
        ),
        integer("IntNative", "A signed integer", "as wide as the platform's word", ""),
        integer(
            "UInt8",
            "An 8-bit unsigned integer, a byte",
            "from 0 to 255; `b'x'` is a byte literal",
            "u8"
        ),
        integer("UInt16", "A 16-bit unsigned integer", "from 0 to 65,535", "u16"),
        integer("UInt32", "A 32-bit unsigned integer", "from 0 to 2^32-1", "u32"),
        integer("UInt64", "A 64-bit unsigned integer", "from 0 to 2^64-1", "u64"),
        integer("UIntNative", "An unsigned integer", "as wide as the platform's word", ""),
        float("Float16", "A 16-bit floating-point number, binary16", "3", "f16"),
        float("Float32", "A 32-bit floating-point number, binary32", "6", "f32"),
        float("Float64", "A 64-bit floating-point number, binary64", "15", "f64"),
        BuiltinDoc(
            "Bool",
            "type Bool",
            "A truth value, `true` or `false`, of the operators `!`, `&&` and `||`."
        ),
        BuiltinDoc(
            "Rune",
            "type Rune",
            "A Unicode character, any of them. Its literals: `r'a'`, `r\"b\"`, an escape `r'\\n'`, a code point " +
                "`r'\\u{4f60}'`."
        ),
        BuiltinDoc(
            "Unit",
            "type Unit",
            "The type of what is evaluated for its effect alone: an assignment, a loop, a function returning nothing " +
                "else. Its one value is `()`; it has `==` and `!=` only."
        ),
        BuiltinDoc(
            "Nothing",
            "type Nothing",
            "The type of no value, a subtype of every type: the type of `break`, `continue`, `return` and `throw`. " +
                "The compiler does not take it written as a type."
        ),
        BuiltinDoc(
            "VArray",
            "type VArray<T, $N>",
            "An array that is a value, of `$N` elements of type `T`, its length an `Int64` literal part of its type: " +
                "`VArray<Int64, $3>`. Made by `VArray<T, $N>({i => ...})` or `VArray<T, $N>(repeat: v)`; it has `[]` and " +
                "`size`. An element is no reference type, enum, lambda (but a `CFunc`) or generic type."
        ),
        BuiltinDoc(
            "CPointer",
            "type CPointer<T>",
            "A C pointer to a `T` that is a `CType`: read, written, moved by arithmetic, compared to null and turned " +
                "into an integer; reading, writing and arithmetic in `unsafe` only."
        ),
        BuiltinDoc(
            "CString",
            "type CString",
            "A C string, `char *`: made by `LibC.mallocCString`, freed by `LibC.free`; `size()`, `isNull()`, " +
                "`startsWith`, `toString()` and the like read it."
        ),
        BuiltinDoc(
            "CFunc",
            "type CFunc<F>",
            "A function C can call: a `foreign` or an `@C` function, or a lambda of this type, which captures " +
                "nothing; called in `unsafe` only."
        )
    ]

/**
 * The annotations the compiler knows, each that `cjsyntax` takes as one (`BuiltinAnnotationName`).
 */
let BUILTIN_ANNOTATION_DOCS: Array<BuiltinDoc> =
    [
        BuiltinDoc(
            "Frozen",
            "@Frozen",
            "The function or property will not change in later versions: neither its signature nor its body, so the " +
                "same compiler with the same options builds the same code of it. On any function but a local one, and " +
                "on a property."
        ),
        BuiltinDoc(
            "When",
            "@When[condition]",
            "Conditional compilation: the import or declaration is compiled only where the condition holds, of " +
                "`os`, `arch`, `env`, `backend`, `cjc_version`, `debug`, `test` and the variables `--cfg` sets: " +
                "`@When[os == \"Linux\" && !debug]`."
        ),
        BuiltinDoc(
            "FastNative",
            "@FastNative",
            "A faster call of a `foreign` function, for a C function that returns soon: one that neither blocks nor " +
                "loops long, nor calls Cangjie."
        ),
        BuiltinDoc(
            "Attribute",
            "@Attribute[name]",
            "Attributes of the declaration that macros read: `std.ast`'s `getAttrs()` and `hasAttr(name)`."
        ),
        BuiltinDoc(
            "Deprecated",
            "@Deprecated[message, since: version, strict: Bool]",
            "The declaration is deprecated: still there, to be removed or changed. A use warns (`-Woff deprecated`), " +
                "or with `strict: true` is an error."
        ),
        BuiltinDoc(
            "OverflowThrowing",
            "@OverflowThrowing",
            "An integer operation or conversion in the function that overflows throws an exception, and " +
                "one the compiler finds is an error: the default."
        ),
        BuiltinDoc(
            "OverflowWrapping",
            "@OverflowWrapping",
            "An integer operation or conversion in the function that overflows wraps around: the bits beyond the " +
                "type are dropped."
        ),
        BuiltinDoc(
            "OverflowSaturating",
            "@OverflowSaturating",
            "An integer operation or conversion in the function that overflows gives the type's minimum or maximum."
        ),
        BuiltinDoc(
            "EnsurePreparedToMock",
            "@EnsurePreparedToMock",
            "On a lambda whose last expression uses a declaration of a package compiled for mocking: prepares it to " +
                "be mocked. Only with `--test` and `--mock`; for test frameworks, rarely written by hand."
        ),
        BuiltinDoc(
            "Annotation",
            "@Annotation[target: [AnnotationKind...]]",
            "The class is an annotation of your own, which reflection reads (`TypeInfo.of(x).findAnnotation<T>()`): " +
                "a class neither `abstract`, `open` nor `sealed`, with a `const init`."
        ),
        BuiltinDoc(
            "C",
            "@C",
            "A function C calls, a `CFunc` called in `unsafe`; or a struct laid out as C's, of `CType` members, " +
                "itself a `CType`."
        ),
        BuiltinDoc(
            "CallingConv",
            "@CallingConv[CDECL]",
            "The calling convention of a `foreign` block or function or a `CFunc`: `CDECL`, clang's C default, the " +
                "only one, and the convention where none is written."
        ),
        BuiltinDoc(
            "JavaMirror",
            "@JavaMirror[\"java.lang.Name\"]",
            "A mirror of the Java type named: its members declared without bodies, for Cangjie to use Java's."
        ),
        BuiltinDoc(
            "JavaImpl",
            "@JavaImpl",
            "A class of Cangjie that Java uses, inheriting mirrored types; the compiler writes its Java wrapper."
        ),
        BuiltinDoc(
            "JavaHasDefault",
            "@JavaHasDefault",
            "A mirrored method of an interface that has a body in Java, `default` there."
        ),
        BuiltinDoc(
            "ObjCMirror",
            "@ObjCMirror[\"Name\"]",
            "A mirror of an Objective-C class or protocol, named as in Objective-C if the mirror's name differs."
        ),
        BuiltinDoc(
            "ObjCImpl",
            "@ObjCImpl",
            "A class of Cangjie that Objective-C uses, through a wrapper class generated for it."
        ),
        BuiltinDoc(
            "ObjCInit",
            "@ObjCInit",
            "A static function mirroring an Objective-C `init` method that cannot be a constructor."
        ),
        BuiltinDoc(
            "ObjCOptional",
            "@ObjCOptional",
            "A mirror of an optional method of a protocol: a call of it throws if the receiver does not implement it."
        ),
        BuiltinDoc(
            "ForeignName",
            "@ForeignName[\"name\"]",
            "The member's name on the other side, Java's or an Objective-C selector, where it is not the mirror's."
        ),
        BuiltinDoc(
            "ForeignGetterName",
            "@ForeignGetterName[\"name\"]",
            "The name of a mirrored Objective-C property's getter, where it is not the default."
        ),
        BuiltinDoc(
            "ForeignSetterName",
            "@ForeignSetterName[\"name\"]",
            "The name of a mirrored Objective-C property's setter, where it is not the default."
        ),
        BuiltinDoc(
            "Intrinsic",
            "@Intrinsic",
            "A function the compiler implements itself: declared without a body, at the top level of a few std " +
                "packages (`std.core`, `std.math`, `std.sync`, …). Each call becomes the compiler's own operation, found " +
                "by the package and the function's name; the function can only be called, never taken as a value."
        ),
        BuiltinDoc(
            "ConstSafe",
            "@ConstSafe",
            "Only in std: the const checker skips the declaration and everything in it, so a `const`, a `const` " +
                "function or a `const init` in it may use what is not const, such as a foreign call. Outside std it is " +
                "no annotation but a macro call."
        ),
        BuiltinDoc(
            "NonProduct",
            "@NonProduct",
            "On a file's `features {}`, in every file of a package or in none: the package is of a source set that " +
                "is not the product of a multiplatform build (`\"product\": false` in what cjc tells cjpm of it)."
        )
    ]

/**
 * The macros of the compiler's own, which no package declares.
 */
let BUILTIN_MACRO_DOCS: Array<BuiltinDoc> =
    [
        BuiltinDoc(
            "sourcePackage",
            "@sourcePackage(): String",
            "The package of the file it is written in, as a `String` literal."
        ),
        BuiltinDoc(
            "sourceFile",
            "@sourceFile(): String",
            "The name of the file it is written in, as a `String` literal."
        ),
        BuiltinDoc(
            "sourceLine",
            "@sourceLine(): Int64",
            "The line it is written on, as an `Int64` literal."
        )
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
 * Every built-in told, for the tests.
 */
func builtinDocs(): Array<BuiltinDoc> {
    BUILTIN_TYPE_DOCS.concat(BUILTIN_ANNOTATION_DOCS).concat(BUILTIN_MACRO_DOCS)
}
