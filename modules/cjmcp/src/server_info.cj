package cjmcp

import fjson.JsonValue

/** Build identity and Python API features, independent of the analyzed workspace. */
func serverInfo(): JsonValue {
    obj(
        [
            ("name", JsonString("cjmcp")),
            ("version", JsonString("0.1.0")),
            (
                "_meta",
                obj(
                    [
                        ("apiVersion", JsonInteger(1)),
                        (
                            "commit",
                            if (BUILD_COMMIT.isEmpty()) {
                                JsonNull
                            } else {
                                JsonString(BUILD_COMMIT)
                            }
                        ),
                        (
                            "dirty",
                            if (BUILD_COMMIT.isEmpty()) { JsonNull } else { JsonBool(BUILD_DIRTY) }
                        ),
                        (
                            "features",
                            JsonArray(
                                [
                                    JsonString("structuredDiagnostics"),
                                    JsonString("worktreeSessions"),
                                    JsonString("checkedSourceChanges"),
                                    JsonString("sourceExcerpts"),
                                    JsonString("outputBudget"),
                                    JsonString("semanticViews")
                                ]
                            )
                        )
                    ]
                )
            )
        ]
    )
}
