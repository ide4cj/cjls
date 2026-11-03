package cjls.handlers

import cjls.lsp_ext.AnalysisStats
import cjls.macros.LspHandler
import cjls.server.*

@LspHandler[readonly]
func handleAnalysisStats(snap: ServerSnapshot, _: Unit): AnalysisStats {
    AnalysisStats(queriesExecuted: snap.analysis.storage.executions)
}
