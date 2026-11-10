from typing import Literal

class SemanticResolutionDiagnostic:
    """

    An inference diagnostic and its owner-qualified anchor in the originating snapshot.

    """
    def __init__(self, __anchor: SemanticObject, __diagnostic: InferenceDiagnostic):
        """
         for type InferenceDiagnostic, see 'loupe.hir/infer.pyi'
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def anchor(self) -> SemanticObject:
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def diagnostic(self) -> InferenceDiagnostic:
        """
         for type InferenceDiagnostic, see 'loupe.hir/infer.pyi'
        """
        ...
class SemanticGenericBinding:
    """

    A final instantiated generic parameter, identified by its real declaration or local binder.

    """
    def __init__(self, __parameter: SemanticObject, __valueType: SemanticType):
        """
         for type SemanticType, see 'loupe/semantic_type.pyi'
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def parameter(self) -> SemanticObject:
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def valueType(self) -> SemanticType:
        """
         for type SemanticType, see 'loupe/semantic_type.pyi'
        """
        ...
class SemanticResolutionStatus:
    """

    Resolution completeness, independent of whether navigation source is available.
    MissingResolutionReason states that inference retained no more precise failure explanation.

    """
    def __eq__(self, __other: SemanticResolutionStatus) -> bool:
        ...
    def __ne__(self, __other: SemanticResolutionStatus) -> bool:
        ...
    kind: Literal['ResolvedMeaning', 'AmbiguousMeaning', 'UnresolvedMeaning', 'UnavailableMeaning']
    class ResolvedMeaning(SemanticResolutionStatus):
        kind: Literal['ResolvedMeaning'] = 'ResolvedMeaning'
        def __init__(self):
            ...
    class AmbiguousMeaning(SemanticResolutionStatus):
        kind: Literal['AmbiguousMeaning'] = 'AmbiguousMeaning'
        def __init__(self):
            ...
    class UnresolvedMeaning(SemanticResolutionStatus):
        kind: Literal['UnresolvedMeaning'] = 'UnresolvedMeaning'
        def __init__(self):
            ...
    class UnavailableMeaning(SemanticResolutionStatus):
        kind: Literal['UnavailableMeaning'] = 'UnavailableMeaning'
        def __init__(self):
            ...
class SemanticResolutionReason:
    """

    Preserved analysis gaps, or an explicit absence of a retained failure explanation.

    """
    ...
    kind: Literal['MissingResolutionReason', 'MissingResolutionData', 'UnavailableBodySource', 'MissingResolutionInput', 'UnsupportedResolution', 'ImportResolutionFailure']
    class MissingResolutionReason(SemanticResolutionReason):
        kind: Literal['MissingResolutionReason'] = 'MissingResolutionReason'
        def __init__(self):
            ...
    class MissingResolutionData(SemanticResolutionReason):
        kind: Literal['MissingResolutionData'] = 'MissingResolutionData'
        def __init__(self):
            ...
    class UnavailableBodySource(SemanticResolutionReason):
        kind: Literal['UnavailableBodySource'] = 'UnavailableBodySource'
        def __init__(self):
            ...
    class MissingResolutionInput(SemanticResolutionReason):
        kind: Literal['MissingResolutionInput'] = 'MissingResolutionInput'
        def __init__(self, __p1: UnknownReason):
            """
             for type UnknownReason, see 'loupe.hir/ty.pyi'
            """
            ...
        @property
        def field0(self) -> UnknownReason:
            ...
        __match_args__ = ('field0')
    class UnsupportedResolution(SemanticResolutionReason):
        kind: Literal['UnsupportedResolution'] = 'UnsupportedResolution'
        def __init__(self, __p1: Todo):
            """
             for type Todo, see 'loupe.hir/ty.pyi'
            """
            ...
        @property
        def field0(self) -> Todo:
            ...
        __match_args__ = ('field0')
    class ImportResolutionFailure(SemanticResolutionReason):
        kind: Literal['ImportResolutionFailure'] = 'ImportResolutionFailure'
        def __init__(self, __p1: ImportError):
            """
             for type ImportError, see 'loupe.hir/imports.pyi'
            """
            ...
        @property
        def field0(self) -> ImportError:
            ...
        __match_args__ = ('field0')
class SemanticCallResolution:
    """

    Retained call evidence. A resolved function value has no declaration target; local named
    functions keep their body-qualified local identity. Initializers and named types stay separate.

    """
    @property
    def isSetter(self) -> bool:
        ...
    @property
    def callee(self) -> SemanticObject:
        """
        The semantic expression whose call resolution is described.
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def status(self) -> SemanticResolutionStatus:
        """
        The resolved, ambiguous, unresolved or unavailable status of this call.
        """
        ...
    def callable(self) -> SemanticObject | None:
        """
        Return the selected declaration or local callable, or None when unresolved.
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    def initializer(self) -> SemanticObject | None:
        """
        Return the selected initializer declaration, or None when absent.
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    def signature(self) -> SemanticType | None:
        """
        Return the retained callable signature type, or None when unavailable.
         for type SemanticType, see 'loupe/semantic_type.pyi'
        """
        ...
    def argumentParameters(self) -> list[int] | None:
        """

        Parameter indices in written argument order, including variadic and trailing-lambda arguments.

        """
        ...
    def bindings(self) -> list[SemanticGenericBinding]:
        """
        Return generic parameter bindings retained for this call.
        """
        ...
class SemanticResolution:
    """

    One source occurrence's retained name, member, import or type-segment meaning and call evidence.
    Status describes identity selection; a resolved declaration may still have an incomplete type.
    Path identities and diagnostic payloads belong to occurrence's snapshot, like SemanticIdentity.

    """
    def __init__(self, __occurrence: SemanticOccurrence, __status: SemanticResolutionStatus, __reason: SemanticResolutionReason | None, __call: SemanticCallResolution | None, __setterCall: SemanticCallResolution | None, __diagnostics: list[SemanticResolutionDiagnostic], __path: PathResolution | None):
        """
         for type PathResolution, see 'loupe.hir/type_path.pyi'
         for type SemanticOccurrence, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def occurrence(self) -> SemanticOccurrence:
        """
         for type SemanticOccurrence, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def status(self) -> SemanticResolutionStatus:
        ...
    @property
    def reason(self) -> SemanticResolutionReason | None:
        ...
    @property
    def call(self) -> SemanticCallResolution | None:
        ...
    @property
    def setterCall(self) -> SemanticCallResolution | None:
        ...
    @property
    def diagnostics(self) -> list[SemanticResolutionDiagnostic]:
        ...
    @property
    def path(self) -> PathResolution | None:
        """
         for type PathResolution, see 'loupe.hir/type_path.pyi'
        """
        ...
class SemanticBodyResolutions:
    """

    A declaration's retained body results and whether its source was available to analysis.
    Empty records alone never establish that an unavailable binary body has no references or calls.

    """
    def __init__(self, __owner: SemanticObject, __status: SemanticResolutionStatus, __reason: SemanticResolutionReason | None, __occurrences: list[SemanticResolution], __calls: list[SemanticCallResolution]):
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def owner(self) -> SemanticObject:
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def status(self) -> SemanticResolutionStatus:
        ...
    @property
    def reason(self) -> SemanticResolutionReason | None:
        ...
    @property
    def occurrences(self) -> list[SemanticResolution]:
        ...
    @property
    def calls(self) -> list[SemanticCallResolution]:
        ...
