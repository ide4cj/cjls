package project_model

/**
 * The cjpm profile used to select dependencies, independent of the target's `@When` conditions.
 * Release matches `cjpm build`; Debug matches `cjpm build -g`.
 */
public enum BuildMode <: Equatable<BuildMode> {
    | Debug
    | Release

    public operator func ==(other: BuildMode): Bool {
        match ((this, other)) {
            case (Debug, Debug) | (Release, Release) => true
            case _ => false
        }
    }
}
