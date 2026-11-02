# Navigate macro expansions

Expansion queries use byte offsets into `analysis.expansion(call).text`:
`hoverInExpansion`, `definitionInExpansion` and `typeDefinitionInExpansion`.
They reject missing expansion text or invalid byte positions. A hover range
belongs to the requested expansion; each navigation target has its own
`expansion` identity (or `None` for source), which selects the text for its ranges.
