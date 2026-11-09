package cjls.handlers

import std.env.getTempDirectory
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.{BinaryModel, ProjectModel}
import project_model.{CangjieHome, hostCfg}
import cjls.server.ServerState

@Test
class SdkWindowWarningTest {
    @TestCase
    func anUnsupportedVersionIsReportedOnlyOnceAcrossLoads(): Unit {
        // arrange
        let state = ServerState()
        let path = getTempDirectory().join("sdk").toString()
        let home = CangjieHome(path, "test", version: "1.0.4")

        // act
        let first = sdkWarning(state, home)

        // assert
        @Expect(first?.contains("1.0.4"), Some(true))
        @Expect(state.hasWarnedSdkVersion)

        // act
        let reloaded = sdkWarning(state, home)

        // assert
        @Expect(reloaded, None<String>)

        // act
        let switched = sdkWarning(state, CangjieHome(path, "test", version: "2.0.0"))

        // assert
        @Expect(switched, None<String>)
    }

    @TestCase[version in [Some("1.0.5"), Some("1.2.0"), None], hasMissingStd in [false, true]]
    func supportedAndUnknownVersionsPreserveContentsWarnings(
        version: ?String,
        hasMissingStd: Bool
    ): Unit {
        // arrange
        let state = ServerState()
        let path = getTempDirectory().join("sdk").toString()
        let home = CangjieHome(path, "test", version: version)
        let binaries: Array<BinaryModel> =
            if (hasMissingStd) { [BinaryModel("std", [])] } else { [] }
        state.setProject(ProjectModel(hostCfg(), [], binaries: binaries))
        let expected = sdkContentsWarning(state, home)

        // act
        let warning = sdkWarning(state, home)

        // assert
        @Expect(warning, expected)
        @Expect(warning.isSome(), hasMissingStd)
        @Expect(!state.hasWarnedSdkVersion)
    }

    @TestCase
    func theWindowWarningKeepsTheMissingStdWarningOnEveryLoad(): Unit {
        // arrange
        let state = ServerState()
        let path = getTempDirectory().join("sdk").toString()
        let home = CangjieHome(path, "test", version: "1.0.4")
        state.setProject(ProjectModel(hostCfg(), [], binaries: [BinaryModel("std", [])]))
        let contentsWarning =
            sdkContentsWarning(state, home) ??
                throw IllegalStateException(
                    "an SDK with no std packages must produce a contents warning"
                )

        // act
        let first = sdkWarning(state, home)

        // assert
        @Expect(first?.contains("1.0.4"), Some(true))
        @Expect(first?.endsWith(contentsWarning), Some(true))

        // act
        let reloaded = sdkWarning(state, home)

        // assert
        @Expect(reloaded, Some(contentsWarning))
    }
}
