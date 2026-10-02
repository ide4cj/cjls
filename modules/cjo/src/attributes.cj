package cjo

/**
 * What cjc marks a declaration with: `Attribute` of `include/cangjie/AST/AttributePack.h`, by the bit each is
 * stored at, mirrored by hand at the schema's commit (`cjo_format.toml`). An attribute is bit `n % 64` of word
 * `n / 64`: one inserted before another moves it, a change of the format that comes with a new major.
 */
public enum Attribute {
    | InReferenceCycle
    | Unreachable
    | ImplicitUsed
    | Imported
    | Global
    | Initialized
    | CompilerAdd
    | Generic
    | Default
    | Static
    | Public
    | Private
    | Protected
    | External
    | Internal
    | Override
    | Redef
    | Abstract
    | Sealed
    | Open
    | Operator
    | Foreign
    | Unsafe
    | Mut
    | HasBroken
    | InStruct
    | InExtend
    | InEnum
    | InClasslike
    | InMacro
    | PrimaryConstructor
    | Constructor
    | EnumConstructor
    | Finalizer
    | IsClonedSourceCode
    | IsCapture
    | InCore
    | NeedAutoBox
    | MacroExpandedNode
    | MacroFunc
    | MacroInvokeFunc
    | MacroInvokeBody
    | LeftValue
    | C
    | SrcImported
    | JavaApp
    | JavaExt
    | StdCall
    | NoMangle
    | InitializationChecked
    | IsBroken
    | GenericInstantiated
    | HasInitial
    | IsVolatile
    | NumericOverflow
    | Intrinsic
    | ToolAdd
    | IsCheckVisited
    | IncreCompile
    | SideEffect
    | ImplicitAdd
    | MainEntry
    | GeneratedToMock
    | IsOutermost
    | IsAnnotation
    | NoReflectInfo
    | MockSupported
    | OpenToMock
    | InterfaceImpl
    | ForTest
    | ContainsMockCreationCall
    | Common
    | FromCommonPart
    | CommonNonExhaustive
    | Specific
    | CommonWithDefault
    | JavaMirror
    | JavaImpl
    | JavaHasDefault
    | JavaMirrorSyntheticWrapper
    | ObjCMirror
    | ObjCImpl
    | ObjCInit
    | ObjCOptional
    | DesugaredMirrorField
    | HasInitedField
    | ObjCMirrorInterfaceHandleWrapper
    | AlreadyLoaded
    | JavaImplRegistryCompanion
    | DoesNotThrow
    | ObjCImplRegistryCompanion
    | ObjCImplMovedMemberProxy

    /** The bit it is stored at. */
    public prop bit: Int64 {
        get() {
            match (this) {
                case Attribute.InReferenceCycle => 0
                case Attribute.Unreachable => 1
                case Attribute.ImplicitUsed => 2
                case Attribute.Imported => 3
                case Attribute.Global => 4
                case Attribute.Initialized => 5
                case Attribute.CompilerAdd => 6
                case Attribute.Generic => 7
                case Attribute.Default => 8
                case Attribute.Static => 9
                case Attribute.Public => 10
                case Attribute.Private => 11
                case Attribute.Protected => 12
                case Attribute.External => 13
                case Attribute.Internal => 14
                case Attribute.Override => 15
                case Attribute.Redef => 16
                case Attribute.Abstract => 17
                case Attribute.Sealed => 18
                case Attribute.Open => 19
                case Attribute.Operator => 20
                case Attribute.Foreign => 21
                case Attribute.Unsafe => 22
                case Attribute.Mut => 23
                case Attribute.HasBroken => 24
                case Attribute.InStruct => 25
                case Attribute.InExtend => 26
                case Attribute.InEnum => 27
                case Attribute.InClasslike => 28
                case Attribute.InMacro => 29
                case Attribute.PrimaryConstructor => 30
                case Attribute.Constructor => 31
                case Attribute.EnumConstructor => 32
                case Attribute.Finalizer => 33
                case Attribute.IsClonedSourceCode => 34
                case Attribute.IsCapture => 35
                case Attribute.InCore => 36
                case Attribute.NeedAutoBox => 37
                case Attribute.MacroExpandedNode => 38
                case Attribute.MacroFunc => 39
                case Attribute.MacroInvokeFunc => 40
                case Attribute.MacroInvokeBody => 41
                case Attribute.LeftValue => 42
                case Attribute.C => 43
                case Attribute.SrcImported => 44
                case Attribute.JavaApp => 45
                case Attribute.JavaExt => 46
                case Attribute.StdCall => 47
                case Attribute.NoMangle => 48
                case Attribute.InitializationChecked => 49
                case Attribute.IsBroken => 50
                case Attribute.GenericInstantiated => 51
                case Attribute.HasInitial => 52
                case Attribute.IsVolatile => 53
                case Attribute.NumericOverflow => 54
                case Attribute.Intrinsic => 55
                case Attribute.ToolAdd => 56
                case Attribute.IsCheckVisited => 57
                case Attribute.IncreCompile => 58
                case Attribute.SideEffect => 59
                case Attribute.ImplicitAdd => 60
                case Attribute.MainEntry => 61
                case Attribute.GeneratedToMock => 62
                case Attribute.IsOutermost => 63
                case Attribute.IsAnnotation => 64
                case Attribute.NoReflectInfo => 65
                case Attribute.MockSupported => 66
                case Attribute.OpenToMock => 67
                case Attribute.InterfaceImpl => 68
                case Attribute.ForTest => 69
                case Attribute.ContainsMockCreationCall => 70
                case Attribute.Common => 71
                case Attribute.FromCommonPart => 72
                case Attribute.CommonNonExhaustive => 73
                case Attribute.Specific => 74
                case Attribute.CommonWithDefault => 75
                case Attribute.JavaMirror => 76
                case Attribute.JavaImpl => 77
                case Attribute.JavaHasDefault => 78
                case Attribute.JavaMirrorSyntheticWrapper => 79
                case Attribute.ObjCMirror => 80
                case Attribute.ObjCImpl => 81
                case Attribute.ObjCInit => 82
                case Attribute.ObjCOptional => 83
                case Attribute.DesugaredMirrorField => 84
                case Attribute.HasInitedField => 85
                case Attribute.ObjCMirrorInterfaceHandleWrapper => 86
                case Attribute.AlreadyLoaded => 87
                case Attribute.JavaImplRegistryCompanion => 88
                case Attribute.DoesNotThrow => 89
                case Attribute.ObjCImplRegistryCompanion => 90
                case Attribute.ObjCImplMovedMemberProxy => 91
            }
        }
    }
}

/**
 * The attributes of a declaration, as `Decl.attributes` reads them: a bit for each, 64 to a word.
 */
public struct Attributes {
    Attributes(let words: FbVector<UInt64>) {}

    public func has(attribute: Attribute): Bool {
        let bit = attribute.bit
        let word = bit / 64
        word < words.size && ((words[word] >> UInt64(bit % 64)) & 1) == 1
    }
}
