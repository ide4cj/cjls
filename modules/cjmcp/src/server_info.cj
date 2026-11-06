package cjmcp

import stdxx.Nullable

/**
 * Build identity and Python API features, independent of the analyzed workspace.
 */
func serverInfo(): McpServerInfo {
    let commit =
        if (BUILD_COMMIT.isEmpty()) {
            Nullable<String>.Null
        } else {
            Nullable<String>.Value(BUILD_COMMIT)
        }
    let dirty =
        if (BUILD_COMMIT.isEmpty()) {
            Nullable<Bool>.Null
        } else {
            Nullable<Bool>.Value(BUILD_DIRTY)
        }
    McpServerInfo(
        "cjmcp",
        "0.1.0",
        McpServerMeta(
            1,
            commit,
            dirty,
            [
                "structuredDiagnostics",
                "worktreeSessions",
                "checkedSourceChanges",
                "sourceExcerpts",
                "outputBudget",
                "semanticViews"
            ]
        )
    )
}
