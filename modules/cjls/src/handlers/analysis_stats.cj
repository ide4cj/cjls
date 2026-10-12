package cjls.handlers

import cjls.lsp_ext.AnalysisStats
import cjls.server.*
import cjls.macros.LspHandler

@LspHandler[readonly]
func handleAnalysisStats(snap: ServerSnapshot, _: Unit): AnalysisStats {
    AnalysisStats(queriesExecuted: snap.analysis.storage.executions)
}
