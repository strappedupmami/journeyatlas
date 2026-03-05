import Foundation

struct AcademicResearchService {
    private enum MethodologyFilter {
        case any
        case metaOrSystematic
        case randomizedControlledTrial
        case highEvidence
    }

    private enum ResearchDomainMode {
        case general
        case biomedical
        case computerScience
    }

    private struct OpenAlexEnvelope: Decodable {
        let results: [OpenAlexWork]
    }

    private struct OpenAlexWork: Decodable {
        let id: String?
        let displayName: String?
        let publicationYear: Int?
        let citedByCount: Int?
        let doi: String?
        let type: String?
        let citedByAPIURL: String?
        let referencedWorks: [String]?
        let abstractInvertedIndex: [String: [Int]]?
        let openAccess: OpenAccess?
        let primaryLocation: PrimaryLocation?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
            case publicationYear = "publication_year"
            case citedByCount = "cited_by_count"
            case doi
            case type
            case citedByAPIURL = "cited_by_api_url"
            case referencedWorks = "referenced_works"
            case abstractInvertedIndex = "abstract_inverted_index"
            case openAccess = "open_access"
            case primaryLocation = "primary_location"
        }
    }

    private struct OpenAccess: Decodable {
        let isOA: Bool?
        let oaURL: String?

        enum CodingKeys: String, CodingKey {
            case isOA = "is_oa"
            case oaURL = "oa_url"
        }
    }

    private struct PrimaryLocation: Decodable {
        let landingPageURL: String?
        let pdfURL: String?

        enum CodingKeys: String, CodingKey {
            case landingPageURL = "landing_page_url"
            case pdfURL = "pdf_url"
        }
    }

    private struct ScoredWork {
        let work: OpenAlexWork
        let score: Double
        let methodLabel: String
        let sampleLabel: String
        let outcomeLabel: String
        let accessLabel: String
        let doiLink: String?
        let bestLink: String?
        let abstract: String
        let backwardReferenceCount: Int
    }

    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "have", "has", "were", "was", "what", "when", "where",
        "which", "will", "would", "could", "should", "into", "about", "your", "you", "our", "their", "they", "them",
        "than", "then", "there", "here", "while", "also", "after", "before", "study", "studies", "paper", "papers",
        "research", "find", "better", "best", "analysis",
    ]

    private static let researchSignals = [
        "research paper", "research papers", "paper", "papers", "academic", "journal", "literature review",
        "systematic review", "meta-analysis", "meta analysis", "randomized controlled trial", "rct",
        "doi", "pubmed", "arxiv", "semantic scholar", "openalex", "citation", "citations",
        "clinical trial", "evidence", "peer reviewed", "peer-reviewed",
    ]

    func looksLikeResearchPrompt(_ prompt: String) -> Bool {
        let normalized = normalizePrompt(prompt).lowercased()
        guard normalized.count >= 16 else { return false }
        return Self.researchSignals.contains { normalized.contains($0) }
    }

    func discover(prompt: String) async -> LocalReasoningOutput? {
        let normalized = normalizePrompt(prompt)
        guard looksLikeResearchPrompt(normalized) else { return nil }

        let methodologyFilter = detectMethodologyFilter(normalized)
        let domainMode = detectDomainMode(normalized)
        let query = buildSearchQuery(normalized)
        guard query.count >= 3, let url = buildOpenAlexURL(query: query) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("AtlasMasaMacOS/1.0 (AcademicDiscovery)", forHTTPHeaderField: "User-Agent")

        let envelope: OpenAlexEnvelope
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                return nil
            }
            envelope = try JSONDecoder().decode(OpenAlexEnvelope.self, from: data)
        } catch {
            return nil
        }

        guard !envelope.results.isEmpty else {
            return noResultOutput(for: normalized, methodologyFilter: methodologyFilter, domainMode: domainMode)
        }

        let queryTokens = tokenize(query)
        guard !queryTokens.isEmpty else { return nil }

        let scored = envelope.results
            .map { scoreWork($0, queryTokens: queryTokens, methodologyFilter: methodologyFilter, domainMode: domainMode) }
            .filter { $0.score > 0.14 }
            .sorted {
                if $0.score == $1.score {
                    return ($0.work.citedByCount ?? 0) > ($1.work.citedByCount ?? 0)
                }
                return $0.score > $1.score
            }

        let top = Array(scored.prefix(10))
        guard !top.isEmpty else {
            return noResultOutput(for: normalized, methodologyFilter: methodologyFilter, domainMode: domainMode)
        }

        let summary = buildSummary(
            prompt: normalized,
            methodologyFilter: methodologyFilter,
            domainMode: domainMode,
            candidateCount: envelope.results.count,
            top: top
        )
        let nextAction = buildNextAction(top: top, methodologyFilter: methodologyFilter, domainMode: domainMode)
        let averageScore = top.map(\.score).reduce(0, +) / Double(max(1, top.count))
        let confidence = clamp(averageScore, min: 0.58, max: 0.95)

        return LocalReasoningOutput(
            model: "atlas-openalex-research-v1",
            summary: trim(summary, maxChars: 2400),
            nextAction: trim(nextAction, maxChars: 280),
            confidence: confidence,
            generatedAt: Date()
        )
    }

    private func buildOpenAlexURL(query: String) -> URL? {
        var components = URLComponents(string: "https://api.openalex.org/works")
        components?.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "sort", value: "relevance_score:desc"),
            URLQueryItem(
                name: "select",
                value: "id,display_name,publication_year,cited_by_count,doi,type,abstract_inverted_index,open_access,primary_location,cited_by_api_url,referenced_works"
            ),
            URLQueryItem(name: "per-page", value: "100"),
        ]
        return components?.url
    }

    private func scoreWork(
        _ work: OpenAlexWork,
        queryTokens: Set<String>,
        methodologyFilter: MethodologyFilter,
        domainMode: ResearchDomainMode
    ) -> ScoredWork {
        let title = work.displayName ?? ""
        let abstract = buildAbstract(work.abstractInvertedIndex)
        let corpus = "\(title) \(abstract)".lowercased()

        let matchCount = queryTokens.filter { corpus.contains($0) }.count
        let overlap = Double(matchCount) / Double(max(4, queryTokens.count))
        let titleMatchCount = queryTokens.filter { title.lowercased().contains($0) }.count
        let titleBoost = Double(titleMatchCount) / Double(max(4, queryTokens.count))
        let citationBoost = min(0.24, log10(Double((work.citedByCount ?? 0) + 1)) / 6.2)
        let recencyBoost: Double
        switch work.publicationYear ?? 0 {
        case 2023...:
            recencyBoost = 0.10
        case 2019...:
            recencyBoost = 0.07
        case 2014...:
            recencyBoost = 0.04
        default:
            recencyBoost = 0.01
        }

        let evidenceBoost = resolveEvidenceBoost(type: work.type, corpus: corpus)
        let methodologyBoost = resolveMethodologyBoost(filter: methodologyFilter, corpus: corpus)
        let domainBoost = resolveDomainBoost(mode: domainMode, corpus: corpus)
        let sampleLabel = extractSampleLabel(corpus)
        let outcomeLabel = extractOutcomeLabel(corpus)
        var score = (overlap * 0.52) + (titleBoost * 0.16) + citationBoost + recencyBoost + evidenceBoost + methodologyBoost + domainBoost
        if sampleLabel != "n/a" { score += 0.02 }
        if outcomeLabel == "Benefit" || outcomeLabel == "Adverse" { score += 0.01 }

        return ScoredWork(
            work: work,
            score: score,
            methodLabel: resolveMethodLabel(type: work.type, corpus: corpus),
            sampleLabel: sampleLabel,
            outcomeLabel: outcomeLabel,
            accessLabel: resolveAccessLabel(work),
            doiLink: normalizeDOI(work.doi),
            bestLink: resolveBestLink(work),
            abstract: abstract,
            backwardReferenceCount: work.referencedWorks?.count ?? 0
        )
    }

    private func resolveEvidenceBoost(type: String?, corpus: String) -> Double {
        let lowerType = (type ?? "").lowercased()
        if corpus.contains("meta-analysis") || corpus.contains("systematic review") {
            return 0.18
        }
        if corpus.contains("randomized") || corpus.contains("controlled trial") {
            return 0.14
        }
        if corpus.contains("cohort") || corpus.contains("longitudinal") {
            return 0.09
        }
        if lowerType.contains("review") {
            return 0.10
        }
        return 0.03
    }

    private func resolveMethodologyBoost(filter: MethodologyFilter, corpus: String) -> Double {
        switch filter {
        case .metaOrSystematic:
            let matched = corpus.contains("meta-analysis") || corpus.contains("systematic review")
            return matched ? 0.22 : -0.14
        case .randomizedControlledTrial:
            let matched = corpus.contains("randomized") || corpus.contains("controlled trial") || containsWholeWord("rct", in: corpus)
            return matched ? 0.22 : -0.14
        case .highEvidence:
            let matched = corpus.contains("meta-analysis") ||
                corpus.contains("systematic review") ||
                corpus.contains("randomized") ||
                corpus.contains("controlled trial")
            return matched ? 0.16 : -0.05
        case .any:
            return 0.0
        }
    }

    private func resolveDomainBoost(mode: ResearchDomainMode, corpus: String) -> Double {
        switch mode {
        case .biomedical:
            return containsAny(corpus, needles: ["patient", "clinical", "therapy", "disease", "health", "treatment"]) ? 0.08 : -0.02
        case .computerScience:
            return containsAny(corpus, needles: ["benchmark", "dataset", "model", "algorithm", "transformer", "accuracy"]) ? 0.08 : -0.02
        case .general:
            return 0.0
        }
    }

    private func resolveMethodLabel(type: String?, corpus: String) -> String {
        if corpus.contains("meta-analysis") || corpus.contains("systematic review") {
            return "Meta/Systematic"
        }
        if corpus.contains("randomized") || corpus.contains("controlled trial") || containsWholeWord("rct", in: corpus) {
            return "RCT"
        }
        if corpus.contains("cohort") || corpus.contains("longitudinal") {
            return "Cohort"
        }
        let lowerType = (type ?? "").lowercased()
        if lowerType.contains("review") {
            return "Review"
        }
        if lowerType.contains("article") {
            return "Article"
        }
        return "Unspecified"
    }

    private func extractSampleLabel(_ corpus: String) -> String {
        if let match = firstRegexCapture(pattern: #"\bn\s*[=:]\s*(\d{2,7})\b"#, in: corpus) {
            return "N=\(match)"
        }
        if let match = firstRegexCapture(pattern: #"\b(\d{2,7})\s+(participants|patients|subjects|adults|children)\b"#, in: corpus) {
            return "N~\(match)"
        }
        return "n/a"
    }

    private func extractOutcomeLabel(_ corpus: String) -> String {
        if containsAny(corpus, needles: ["no significant", "not significant", "mixed results", "inconclusive", "heterogeneity"]) {
            return "Mixed"
        }
        if containsAny(corpus, needles: ["increase risk", "adverse", "harm", "worse", "toxicity"]) {
            return "Adverse"
        }
        if containsAny(corpus, needles: ["improve", "effective", "benefit", "reduced", "increase", "positive"]) {
            return "Benefit"
        }
        return "Neutral"
    }

    private func resolveAccessLabel(_ work: OpenAlexWork) -> String {
        if !(work.primaryLocation?.pdfURL ?? "").isEmpty {
            return "PDF"
        }
        if work.openAccess?.isOA == true || !(work.openAccess?.oaURL ?? "").isEmpty {
            return "Open"
        }
        if !(work.doi ?? "").isEmpty {
            return "DOI"
        }
        return "Abstract"
    }

    private func resolveBestLink(_ work: OpenAlexWork) -> String? {
        firstNonEmpty([
            work.primaryLocation?.pdfURL,
            work.openAccess?.oaURL,
            work.primaryLocation?.landingPageURL,
            normalizeDOI(work.doi),
            work.id,
        ])
    }

    private func buildSummary(
        prompt: String,
        methodologyFilter: MethodologyFilter,
        domainMode: ResearchDomainMode,
        candidateCount: Int,
        top: [ScoredWork]
    ) -> String {
        var lines: [String] = []
        lines.append("Academic discovery: scanned \(candidateCount) OpenAlex papers and ranked top \(top.count) by abstract relevance + evidence strength.")
        lines.append("Domain mode: \(domainModeLabel(domainMode)).")
        lines.append("Methodology mode: \(methodologyFilterLabel(methodologyFilter)).")
        lines.append("")
        lines.append("Comparative Matrix (Top Matches)")
        lines.append("# | Year | Citations | Method | Sample | Outcome | Access")
        for (index, item) in top.enumerated() {
            let year = item.work.publicationYear.map(String.init) ?? "n/a"
            let citations = item.work.citedByCount.map(String.init) ?? "0"
            lines.append("\(index + 1) | \(year) | \(citations) | \(item.methodLabel) | \(item.sampleLabel) | \(item.outcomeLabel) | \(item.accessLabel)")
        }

        lines.append("")
        lines.append("Direct Sources (anti-hallucination links)")
        for (index, item) in top.prefix(6).enumerated() {
            let title = trim(item.work.displayName ?? "Untitled work", maxChars: 120)
            let year = item.work.publicationYear.map(String.init) ?? "n/a"
            let source = item.bestLink ?? item.doiLink ?? item.work.id ?? "no-link"
            lines.append("\(index + 1). \(title) (\(year)) -> \(source)")
        }

        if let seed = top.first {
            lines.append("")
            lines.append("Citation Snowball")
            if let forward = seed.work.citedByAPIURL, !forward.isEmpty {
                lines.append("Forward citations API: \(forward)")
            }
            lines.append("Backward references available: \(seed.backwardReferenceCount)")
            for ref in (seed.work.referencedWorks ?? []).prefix(8) {
                lines.append("- \(normalizeOpenAlexReference(ref))")
            }
        }

        lines.append("")
        lines.append(buildConsensusLine(top))

        let explorerHints = topicExplorerHints(for: prompt, mode: domainMode)
        if !explorerHints.isEmpty {
            lines.append("")
            lines.append("Topic Explorer")
            for hint in explorerHints {
                lines.append("- \(hint)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func buildNextAction(top: [ScoredWork], methodologyFilter: MethodologyFilter, domainMode: ResearchDomainMode) -> String {
        guard let first = top.first else {
            return "Broaden the query, then rerun with clearer population, outcome, and method filter."
        }
        let methodHint: String
        switch methodologyFilter {
        case .metaOrSystematic:
            methodHint = "meta-analysis/systematic-review quality"
        case .randomizedControlledTrial:
            methodHint = "RCT protocol quality and sample design"
        case .highEvidence:
            methodHint = "highest-evidence hierarchy"
        case .any:
            methodHint = "method and sample quality"
        }

        let domainHint: String
        switch domainMode {
        case .biomedical:
            domainHint = "clinical population and intervention"
        case .computerScience:
            domainHint = "benchmark, dataset, and metric"
        case .general:
            domainHint = "population, method, and measured outcome"
        }

        let seedLink = first.bestLink ?? first.doiLink ?? first.work.id ?? "top source"
        return "Open top 3 links, compare \(methodHint), then run citation snowballing (forward/backward) from the top seed. Validate \(domainHint). Start with: \(seedLink)"
    }

    private func buildConsensusLine(_ top: [ScoredWork]) -> String {
        var supportive = 0
        var mixed = 0
        var cautious = 0

        for item in top {
            let text = "\(item.work.displayName ?? "") \(item.abstract)".lowercased()
            if containsAny(text, needles: ["no significant", "not significant", "mixed results", "inconclusive", "heterogeneity"]) {
                mixed += 1
            } else if containsAny(text, needles: ["improve", "effective", "benefit", "reduced", "increase", "positive"]) {
                supportive += 1
            } else {
                cautious += 1
            }
        }

        return "Consensus snapshot: supportive=\(supportive), mixed/inconclusive=\(mixed), cautious/neutral=\(cautious)."
    }

    private func noResultOutput(for prompt: String, methodologyFilter: MethodologyFilter, domainMode: ResearchDomainMode) -> LocalReasoningOutput {
        let hints = topicExplorerHints(for: prompt, mode: domainMode)
        let hintLine: String
        if hints.isEmpty {
            hintLine = "Try adding target population, timeframe, and one methodology requirement."
        } else {
            hintLine = "Try one of these sub-queries: \(hints.joined(separator: " | "))"
        }

        return LocalReasoningOutput(
            model: "atlas-openalex-research-v1",
            summary: "Academic discovery did not find strong matches under \(methodologyFilterLabel(methodologyFilter)) mode (\(domainModeLabel(domainMode))). \(hintLine)",
            nextAction: "Broaden the query, remove one strict constraint, and rerun.",
            confidence: 0.52,
            generatedAt: Date()
        )
    }

    private func topicExplorerHints(for prompt: String, mode: ResearchDomainMode) -> [String] {
        let tokens = tokenize(prompt)
        if tokens.count > 4 {
            return []
        }

        let lower = prompt.lowercased()
        if containsAny(lower, needles: ["ai", "llm", "machine learning"]) || mode == .computerScience {
            return [
                "Benchmark + dataset + metric comparison",
                "Ablation and failure-mode analysis",
                "Latency/cost/quality tradeoff studies",
            ]
        }
        if containsAny(lower, needles: ["health", "medical", "clinical"]) || mode == .biomedical {
            return [
                "Population + intervention + outcome framing",
                "RCT and meta-analysis evidence split",
                "Safety/adverse-event incidence comparison",
            ]
        }
        if containsAny(lower, needles: ["education", "learning", "school"]) {
            return [
                "Personalized learning outcomes in K-12",
                "Academic integrity + AI policy outcomes",
                "Teacher workload effects from AI copilots",
            ]
        }
        if containsAny(lower, needles: ["business", "revenue", "sales", "growth"]) {
            return [
                "Customer acquisition strategy meta-analyses",
                "Retention intervention effect sizes",
                "Pricing strategy evidence in SaaS and services",
            ]
        }

        return [
            "Target population + intervention + outcome",
            "Comparative method (A/B or treatment/control)",
            "Time horizon and measurable endpoint",
        ]
    }

    private func detectMethodologyFilter(_ prompt: String) -> MethodologyFilter {
        let lower = prompt.lowercased()
        if containsAny(lower, needles: ["meta-analysis", "meta analysis", "systematic review"]) {
            return .metaOrSystematic
        }
        if containsAny(lower, needles: ["randomized controlled trial", "randomized", "rct", "controlled trial"]) {
            return .randomizedControlledTrial
        }
        if containsAny(lower, needles: ["high evidence", "strong evidence", "evidence quality", "methodology"]) {
            return .highEvidence
        }
        return .any
    }

    private func detectDomainMode(_ prompt: String) -> ResearchDomainMode {
        let lower = prompt.lowercased()
        if containsAny(lower, needles: ["pubmed", "clinical", "medical", "medicine", "biomedical", "patient", "therapy", "health"]) {
            return .biomedical
        }
        if containsAny(lower, needles: ["arxiv", "machine learning", "deep learning", "llm", "nlp", "computer vision", "benchmark", "algorithm"]) {
            return .computerScience
        }
        return .general
    }

    private func methodologyFilterLabel(_ filter: MethodologyFilter) -> String {
        switch filter {
        case .metaOrSystematic:
            return "Meta-analysis / Systematic review prioritized"
        case .randomizedControlledTrial:
            return "Randomized controlled trials prioritized"
        case .highEvidence:
            return "High-evidence papers prioritized"
        case .any:
            return "General evidence mix"
        }
    }

    private func domainModeLabel(_ mode: ResearchDomainMode) -> String {
        switch mode {
        case .biomedical:
            return "Biomedical (PubMed-like evidence focus)"
        case .computerScience:
            return "Computer Science / AI (arXiv-like benchmark focus)"
        case .general:
            return "General"
        }
    }

    private func buildSearchQuery(_ prompt: String) -> String {
        var cleaned = prompt
        let removable = [
            "meta-analysis", "meta analysis", "systematic review", "randomized", "rct", "trial", "doi", "pdf", "citation",
        ]
        for token in removable {
            cleaned = cleaned.replacingOccurrences(
                of: "\\b" + NSRegularExpression.escapedPattern(for: token) + "\\b",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return trim(collapseWhitespace(cleaned), maxChars: 180)
    }

    private func buildAbstract(_ invertedIndex: [String: [Int]]?) -> String {
        guard let invertedIndex, !invertedIndex.isEmpty else { return "" }
        let maxPosition = invertedIndex.values.flatMap { $0 }.max() ?? -1
        guard maxPosition >= 0, maxPosition <= 4096 else { return "" }

        var ordered = Array(repeating: "", count: maxPosition + 1)
        for (token, positions) in invertedIndex {
            for position in positions where position >= 0 && position < ordered.count && ordered[position].isEmpty {
                ordered[position] = token
            }
        }
        let joined = ordered.filter { !$0.isEmpty }.joined(separator: " ")
        return trim(collapseWhitespace(joined), maxChars: 4000)
    }

    private func tokenize(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count >= 3 && !Self.stopwords.contains($0) }
        )
    }

    private func normalizePrompt(_ value: String) -> String {
        collapseWhitespace(value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func collapseWhitespace(_ value: String) -> String {
        value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func normalizeDOI(_ raw: String?) -> String? {
        guard var trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        if trimmed.lowercased().hasPrefix("doi:") {
            trimmed = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "https://doi.org/\(trimmed)"
    }

    private func normalizeOpenAlexReference(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ""
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        if trimmed.uppercased().hasPrefix("W") {
            return "https://openalex.org/\(trimmed)"
        }
        return trimmed
    }

    private func containsAny(_ text: String, needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func containsWholeWord(_ needle: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: needle)
        return text.range(of: "\\b\(escaped)\\b", options: .regularExpression) != nil
    }

    private func firstRegexCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[captureRange])
    }

    private func trim(_ value: String, maxChars: Int) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > maxChars else { return cleaned }
        let index = cleaned.index(cleaned.startIndex, offsetBy: max(0, maxChars))
        return String(cleaned[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        if value < minValue { return minValue }
        if value > maxValue { return maxValue }
        return value
    }
}
