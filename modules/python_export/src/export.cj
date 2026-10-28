macro package python_export

import std.ast.*
import std.collection.*

/** Read-only native result bindings. Other hosts retain the original declaration unchanged. */
@When[os == "Linux"]
public macro PythonExport(input: Tokens): Tokens {
    let (decl, _) = parseDeclFragment(input)
    let name = decl.identifier
    let text = name.value
    let classId = Token(IDENTIFIER, "${text}__PythonClass")
    let descriptor = Token(IDENTIFIER, "${text}__PythonDescriptor")
    let properties = propertyBindings(decl, name)
    let enumMethods = enumBindings(decl, name)
    let exports =
        quote(
            private var $classId = CPointer<Unit>()
            private var $descriptor: ?PyNativeDescriptor = None
            extend $name <: IntoPy<$name> & FromPy<$name> {
                public static func pyClass(marker!: PyInteropTypeMarker<$name> = PyInteropTypeMarker()): PyObj {
                    withGIL {
                        if ($classId.isNull()) {
                            let spec = PyNativeDescriptor()
                            spec.setInit({ self, _, kwargs =>
                                unsafe {
                                    if (kwargs.isNull()) {
                                        Python.setTypeErr("analysis values are created by the workspace")
                                        return -1
                                    }
                                    let key = LibC.mallocCString("__cangjie_id")
                                    let id = PyDict_GetItemString(kwargs, key.getChars())
                                    LibC.free(key)
                                    if (id.isNull()) {
                                        Python.setTypeErr("analysis values are created by the workspace")
                                        return -1
                                    }
                                    var storage = self.read()
                                    storage.registryId = PyLong_AsLongLong(id)
                                    self.write(storage)
                                    return 0
                                }
                            })
                            unsafe {
                                $properties
                                $enumMethods
                            }
                            $descriptor = spec
                            unsafe {
                                $classId = PyType_FromSpec(spec.buildSpecPtr(LibC.mallocCString($text).getChars()))
                                if ($classId.isNull()) { throw PythonException(PYLOG.getPythonErr()) }
                                PyObject_SetAttrString($classId, LibC.mallocCString("__cangjie_identity__"), PyUnicode_FromString(LibC.mallocCString($text)))
                            }
                        }
                        PyType(PythonInteropReference($classId))
                    }
                }
                public func toPyObj(marker!: PyInteropTypeMarker<$name> = PyInteropTypeMarker()): PyObj {
                    $name.pyClass()
                    PyProxy(this, $classId, $text)
                }
                public static func fromNativePyObj(value: NativePyObj, marker!: PyInteropTypeMarker<$name> = PyInteropTypeMarker()): ?$name {
                    unsafe { PyProxy.getFromRegistry<$name>(CPointer<CangjiePyObjStorage>(value)) }
                }
                public static func fromPyObj(value: PyObj, marker!: PyInteropTypeMarker<$name> = PyInteropTypeMarker()): ?$name {
                    fromNativePyObj(value.getRef().getPtr())
                }
            }
        )
    input + exports
}

@When[os != "Linux"]
public macro PythonExport(input: Tokens): Tokens {
    input
}

func propertyBindings(decl: Decl, owner: Token): Tokens {
    let fields = ArrayList<Token>()
    let members =
        match (decl) {
            case one: ClassDecl => one.body.decls
            case one: StructDecl => one.body.decls
            case _ => ArrayList<Decl>()
        }
    for (member in members) {
        if (member.modifiers.toArray().any { modifier => modifier.keyword.kind == PRIVATE }) {
            continue
        }
        match (member) {
            case ctor: PrimaryCtorDecl =>
                for (param in ctor.funcParams) {
                    let tokens = param.toTokens()
                    if (tokens.iterator().any { token => token.kind == PRIVATE }) {
                        continue
                    }
                    if (tokens.iterator().any { token => token.kind == LET || token.kind == VAR }) {
                        fields.add(param.identifier)
                    }
                }
            case field: VarDecl => fields.add(field.identifier)
            case field: PropDecl => fields.add(field.identifier)
            case _ => ()
        }
    }
    let result = Tokens()
    for (field in fields) {
        let text = field.value
        result
            .append(
                quote(
                    spec.addGetSet(PyGetSetDef(
                        name: LibC.mallocCString($text).getChars(),
                        getter: { self, _ =>
                            withGIL {
                                unsafe {
                                    let value = PyProxy.getFromRegistry<$owner>(CPointer<CangjiePyObjStorage>(self)) ?? return CPointer<Unit>()
                                    toNativePyObj(value.$field)
                                }
                            }
                        }
                    ))
                )
            )
    }
    result
}

func enumBindings(decl: Decl, owner: Token): Tokens {
    let enumeration = (decl as EnumDecl) ?? return Tokens()
    let arms = Tokens()
    for (constructor in enumeration.constructors) {
        if (!constructor.typeArguments.isEmpty()) {
            diagReport(
                DiagReportLevel.ERROR,
                constructor.toTokens(),
                "PythonExport currently supports enums without payloads",
                ""
            )
            return Tokens()
        }
        let id = constructor.identifier
        let text = id.value
        arms.append(quote(case $owner.$id => $text))
    }
    quote(
        spec.addMethod(PyMethodDef(
            name: LibC.mallocCString("toString").getChars(), flags: METH_VARARGS | METH_KEYWORDS,
            meth: { self, _, _ =>
                withGIL {
                    unsafe {
                        let value = PyProxy.getFromRegistry<$owner>(CPointer<CangjiePyObjStorage>(self)) ?? return CPointer<Unit>()
                        let text = match (value) { $arms }
                        toNativePyObj(text)
                    }
                }
            }
        ))
    )
}
