import Foundation

struct AcademicResearchService {
    private enum MethodologyFilter {
        case any
        case metaOrSystematic
        case randomizedControlledTrial
        case highEvidence
    }

    private enum ResearchSourceMode {
        case auto
        case openAlex
        case semanticScholar
        case pubMed
        case arxiv
        case crossCheck
    }

    private enum ResearchDomainMode {
        case general
        case biomedical
        case computerScience
    }

    private struct OpenAlexEnvelope: Decodable {
        let results: [OpenAlexWork]
    }

    private struct PubMedSearchEnvelope: Decodable {
        let esearchresult: PubMedSearchResult
    }

    private struct PubMedSearchResult: Decodable {
        let idlist: [String]
    }

    private struct SemanticScholarEnvelope: Decodable {
        let data: [SemanticScholarPaper]
    }

    private struct SemanticScholarPaper: Decodable {
        let paperId: String?
        let title: String?
        let year: Int?
        let citationCount: Int?
        let abstract: String?
        let url: String?
        let openAccessPdf: SemanticScholarPDF?
        let externalIds: SemanticScholarExternalIDs?
        let publicationTypes: [String]?
        let referenceCount: Int?
    }

    private struct SemanticScholarPDF: Decodable {
        let url: String?
    }

    private struct SemanticScholarExternalIDs: Decodable {
        let doi: String?

        enum CodingKeys: String, CodingKey {
            case doi = "DOI"
        }
    }

    private struct UnpaywallResponse: Decodable {
        let isOA: Bool?
        let bestOALocation: UnpaywallLocation?
        let doiURL: String?

        enum CodingKeys: String, CodingKey {
            case isOA = "is_oa"
            case bestOALocation = "best_oa_location"
            case doiURL = "doi_url"
        }
    }

    private struct UnpaywallLocation: Decodable {
        let url: String?
        let urlForPDF: String?

        enum CodingKeys: String, CodingKey {
            case url
            case urlForPDF = "url_for_pdf"
        }
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
        let sourceMode = detectSourceMode(normalized)
        let query = buildSearchQuery(normalized)
        guard query.count >= 3 else { return nil }

        let candidates = await fetchCandidates(query: query, domainMode: domainMode, sourceMode: sourceMode)

        guard !candidates.isEmpty else {
            return noResultOutput(
                for: normalized,
                methodologyFilter: methodologyFilter,
                domainMode: domainMode,
                sourceMode: sourceMode
            )
        }

        let queryTokens = tokenize(query)
        guard !queryTokens.isEmpty else { return nil }

        let scored = candidates
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
            return noResultOutput(
                for: normalized,
                methodologyFilter: methodologyFilter,
                domainMode: domainMode,
                sourceMode: sourceMode
            )
        }

        let summary = buildSummary(
            prompt: normalized,
            methodologyFilter: methodologyFilter,
            domainMode: domainMode,
            sourceMode: sourceMode,
            candidateCount: candidates.count,
            top: top
        )
        let nextAction = buildNextAction(top: top, methodologyFilter: methodologyFilter, domainMode: domainMode, sourceMode: sourceMode)
        let averageScore = top.map(\.score).reduce(0, +) / Double(max(1, top.count))
        let confidence = clamp(averageScore, min: 0.58, max: 0.95)

        return LocalReasoningOutput(
            model: "atlas-academic-discovery-v3",
            summary: trim(summary, maxChars: 2400),
            nextAction: trim(nextAction, maxChars: 280),
            confidence: confidence,
            generatedAt: Date()
        )
    }

    private func fetchCandidates(query: String, domainMode: ResearchDomainMode, sourceMode: ResearchSourceMode) async -> [OpenAlexWork] {
        async let openAlex = fetchOpenAlexWorks(query: query, sourceMode: sourceMode)
        async let semanticScholar = fetchSemanticScholarWorks(query: query, domainMode: domainMode, sourceMode: sourceMode)
        async let pubMed = fetchPubMedWorks(query: query, domainMode: domainMode, sourceMode: sourceMode)
        async let arxiv = fetchArxivWorks(query: query, domainMode: domainMode, sourceMode: sourceMode)

        let merged = await (openAlex + semanticScholar + pubMed + arxiv)
        let deduped = deduplicateWorks(merged)
        return await enrichWorksWithUnpaywall(deduped)
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

    private func buildSemanticScholarURL(query: String, domainMode: ResearchDomainMode) -> URL? {
        var components = URLComponents(string: "https://api.semanticscholar.org/graph/v1/paper/search")
        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: domainMode == .computerScience ? "30" : "20"),
            URLQueryItem(name: "fields", value: "paperId,title,year,abstract,url,citationCount,publicationTypes,externalIds,openAccessPdf,referenceCount"),
        ]
        if domainMode == .computerScience {
            queryItems.append(URLQueryItem(name: "fieldsOfStudy", value: "Computer Science"))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    private func fetchOpenAlexWorks(query: String, sourceMode: ResearchSourceMode) async -> [OpenAlexWork] {
        guard sourceMode != .semanticScholar, sourceMode != .pubMed, sourceMode != .arxiv, let url = buildOpenAlexURL(query: query) else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("AtlasMasaMacOS/1.0 (AcademicDiscovery)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                return []
            }
            let envelope = try JSONDecoder().decode(OpenAlexEnvelope.self, from: data)
            return envelope.results
        } catch {
            return []
        }
    }

    private func fetchSemanticScholarWorks(query: String, domainMode: ResearchDomainMode, sourceMode: ResearchSourceMode) async -> [OpenAlexWork] {
        guard sourceMode != .openAlex, sourceMode != .pubMed, sourceMode != .arxiv, let url = buildSemanticScholarURL(query: query, domainMode: domainMode) else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("AtlasMasaMacOS/1.0 (AcademicDiscovery)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                return []
            }
            let envelope = try JSONDecoder().decode(SemanticScholarEnvelope.self, from: data)
            return envelope.data.map { paper in
                OpenAlexWork(
                    id: paper.url ?? paper.paperId.map { "https://www.semanticscholar.org/paper/\($0)" },
                    displayName: paper.title,
                    publicationYear: paper.year,
                    citedByCount: paper.citationCount,
                    doi: paper.externalIds?.doi,
                    type: paper.publicationTypes?.first,
                    citedByAPIURL: nil,
                    referencedWorks: [],
                    abstractInvertedIndex: makeInvertedIndex(from: paper.abstract),
                    openAccess: OpenAccess(isOA: !(paper.openAccessPdf?.url ?? "").isEmpty, oaURL: paper.openAccessPdf?.url),
                    primaryLocation: PrimaryLocation(landingPageURL: paper.url, pdfURL: paper.openAccessPdf?.url)
                )
            }
        } catch {
            return []
        }
    }

    private func fetchPubMedWorks(query: String, domainMode: ResearchDomainMode, sourceMode: ResearchSourceMode) async -> [OpenAlexWork] {
        guard shouldFetchPubMed(domainMode: domainMode, sourceMode: sourceMode),
              let searchURL = buildPubMedSearchURL(query: query)
        else { return [] }

        var searchRequest = URLRequest(url: searchURL)
        searchRequest.httpMethod = "GET"
        searchRequest.timeoutInterval = 18
        searchRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        searchRequest.setValue("AtlasMasaMacOS/1.0 (AcademicDiscovery)", forHTTPHeaderField: "User-Agent")

        do {
            let (searchData, searchResponse) = try await URLSession.shared.data(for: searchRequest)
            guard let http = searchResponse as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else { return [] }
            let envelope = try JSONDecoder().decode(PubMedSearchEnvelope.self, from: searchData)
            let ids = Array(envelope.esearchresult.idlist.prefix(12))
            guard !ids.isEmpty, let fetchURL = buildPubMedFetchURL(ids: ids) else { return [] }

            var fetchRequest = URLRequest(url: fetchURL)
            fetchRequest.httpMethod = "GET"
            fetchRequest.timeoutInterval = 18
            fetchRequest.setValue("application/xml,text/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            fetchRequest.setValue("AtlasMasaMacOS/1.0 (AcademicDiscovery)", forHTTPHeaderField: "User-Agent")

            let (fetchData, fetchResponse) = try await URLSession.shared.data(for: fetchRequest)
            guard let fetchHTTP = fetchResponse as? HTTPURLResponse, (200 ... 299).contains(fetchHTTP.statusCode),
                  let xml = String(data: fetchData, encoding: .utf8)
            else { return [] }

            return parsePubMedArticles(xml)
        } catch {
            return []
        }
    }

    private func fetchArxivWorks(query: String, domainMode: ResearchDomainMode, sourceMode: ResearchSourceMode) async -> [OpenAlexWork] {
        guard shouldFetchArxiv(domainMode: domainMode, sourceMode: sourceMode),
              let url = buildArxivURL(query: query)
        else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 18
        request.setValue("application/atom+xml,text/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("AtlasMasaMacOS/1.0 (AcademicDiscovery)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
                  let xml = String(data: data, encoding: .utf8)
            else { return [] }
            return parseArxivEntries(xml)
        } catch {
            return []
        }
    }

    private func buildPubMedSearchURL(query: String) -> URL? {
        var components = URLComponents(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi")
        components?.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "retmode", value: "json"),
            URLQueryItem(name: "retmax", value: "12"),
            URLQueryItem(name: "sort", value: "relevance"),
            URLQueryItem(name: "term", value: query),
        ]
        return components?.url
    }

    private func buildPubMedFetchURL(ids: [String]) -> URL? {
        var components = URLComponents(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi")
        components?.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "retmode", value: "xml"),
            URLQueryItem(name: "id", value: ids.joined(separator: ",")),
        ]
        return components?.url
    }

    private func buildArxivURL(query: String) -> URL? {
        var components = URLComponents(string: "https://export.arxiv.org/api/query")
        components?.queryItems = [
            URLQueryItem(name: "search_query", value: "all:\(query)"),
            URLQueryItem(name: "start", value: "0"),
            URLQueryItem(name: "max_results", value: "20"),
            URLQueryItem(name: "sortBy", value: "relevance"),
            URLQueryItem(name: "sortOrder", value: "descending"),
        ]
        return components?.url
    }

    private func shouldFetchPubMed(domainMode: ResearchDomainMode, sourceMode: ResearchSourceMode) -> Bool {
        switch sourceMode {
        case .openAlex, .semanticScholar, .arxiv:
            return false
        case .pubMed:
            return true
        case .auto, .crossCheck:
            return domainMode == .biomedical
        }
    }

    private func shouldFetchArxiv(domainMode: ResearchDomainMode, sourceMode: ResearchSourceMode) -> Bool {
        switch sourceMode {
        case .openAlex, .semanticScholar, .pubMed:
            return false
        case .arxiv:
            return true
        case .auto, .crossCheck:
            return domainMode == .computerScience
        }
    }

    private func parsePubMedArticles(_ xml: String) -> [OpenAlexWork] {
        let blocks = regexMatches(pattern: #"<PubmedArticle[\s\S]*?</PubmedArticle>"#, in: xml)
        return blocks.compactMap { block in
            let title = decodeXML(firstRegexCapture(pattern: #"<ArticleTitle>([\s\S]*?)</ArticleTitle>"#, in: block) ?? "")
            guard !title.isEmpty else { return nil }
            let pmid = decodeXML(firstRegexCapture(pattern: #"<PMID[^>]*>([^<]+)</PMID>"#, in: block) ?? "")
            let yearString = firstRegexCapture(pattern: #"<PubDate>[\s\S]*?<Year>(\d{4})</Year>"#, in: block)
                ?? firstRegexCapture(pattern: #"<ArticleDate[^>]*>[\s\S]*?<Year>(\d{4})</Year>"#, in: block)
            let abstractParts = regexMatches(pattern: #"<AbstractText[^>]*>([\s\S]*?)</AbstractText>"#, in: block, captureGroup: 1).map(decodeXML)
            let abstract = collapseWhitespace(abstractParts.joined(separator: " "))
            let doi = firstRegexCapture(pattern: #"<ArticleId IdType="doi">([^<]+)</ArticleId>"#, in: block)
            let type = block.lowercased().contains("<publicationtype>review</publicationtype>") ? "review" : "article"
            let landingURL = pmid.isEmpty ? nil : "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/"
            return OpenAlexWork(
                id: landingURL,
                displayName: title,
                publicationYear: yearString.flatMap(Int.init),
                citedByCount: nil,
                doi: doi,
                type: type,
                citedByAPIURL: nil,
                referencedWorks: [],
                abstractInvertedIndex: makeInvertedIndex(from: abstract),
                openAccess: OpenAccess(isOA: false, oaURL: nil),
                primaryLocation: PrimaryLocation(landingPageURL: landingURL, pdfURL: nil)
            )
        }
    }

    private func parseArxivEntries(_ xml: String) -> [OpenAlexWork] {
        let blocks = regexMatches(pattern: #"<entry>([\s\S]*?)</entry>"#, in: xml, captureGroup: 1)
        return blocks.compactMap { block in
            let title = collapseWhitespace(decodeXML(firstRegexCapture(pattern: #"<title>([\s\S]*?)</title>"#, in: block) ?? ""))
            guard !title.isEmpty else { return nil }
            let summary = collapseWhitespace(decodeXML(firstRegexCapture(pattern: #"<summary>([\s\S]*?)</summary>"#, in: block) ?? ""))
            let id = decodeXML(firstRegexCapture(pattern: #"<id>([^<]+)</id>"#, in: block) ?? "")
            let year = firstRegexCapture(pattern: #"<published>(\d{4})-"#, in: block).flatMap(Int.init)
            let doi = decodeXML(firstRegexCapture(pattern: #"<arxiv:doi[^>]*>([^<]+)</arxiv:doi>"#, in: block) ?? "")
            let pdf = decodeXML(firstRegexCapture(pattern: #"<link[^>]*title="pdf"[^>]*href="([^"]+)""#, in: block) ?? "")
            return OpenAlexWork(
                id: id.isEmpty ? nil : id,
                displayName: title,
                publicationYear: year,
                citedByCount: nil,
                doi: doi.isEmpty ? nil : doi,
                type: "preprint",
                citedByAPIURL: nil,
                referencedWorks: [],
                abstractInvertedIndex: makeInvertedIndex(from: summary),
                openAccess: OpenAccess(isOA: true, oaURL: pdf.isEmpty ? nil : pdf),
                primaryLocation: PrimaryLocation(landingPageURL: id.isEmpty ? nil : id, pdfURL: pdf.isEmpty ? nil : pdf)
            )
        }
    }

    private func deduplicateWorks(_ works: [OpenAlexWork]) -> [OpenAlexWork] {
        var seen: Set<String> = []
        var deduped: [OpenAlexWork] = []
        for work in works {
            let title = (work.displayName ?? "").lowercased()
            let year = work.publicationYear.map(String.init) ?? "n/a"
            let doi = normalizeDOI(work.doi) ?? ""
            let key = !doi.isEmpty ? doi : "\(title)|\(year)"
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            deduped.append(work)
        }
        return deduped
    }

    private func enrichWorksWithUnpaywall(_ works: [OpenAlexWork]) async -> [OpenAlexWork] {
        guard let email = unpaywallEmail() else { return works }

        let enriched = await withTaskGroup(of: (Int, OpenAlexWork?).self, returning: [Int: OpenAlexWork].self) { group in
            for (index, work) in works.enumerated() {
                let hasOpenLink = !(work.primaryLocation?.pdfURL ?? "").isEmpty ||
                    !(work.openAccess?.oaURL ?? "").isEmpty ||
                    work.openAccess?.isOA == true
                guard !hasOpenLink,
                      let doi = normalizeDOI(work.doi),
                      index < 12
                else { continue }

                group.addTask {
                    let enriched = await fetchUnpaywallEnrichment(for: work, doiURL: doi, email: email)
                    return (index, enriched)
                }
            }

            var collected: [Int: OpenAlexWork] = [:]
            for await (index, work) in group {
                if let work {
                    collected[index] = work
                }
            }
            return collected
        }

        return works.enumerated().map { index, work in
            enriched[index] ?? work
        }
    }

    private func fetchUnpaywallEnrichment(for work: OpenAlexWork, doiURL: String, email: String) async -> OpenAlexWork? {
        guard let url = buildUnpaywallURL(for: doiURL, email: email) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AtlasMasaMacOS/1.0 (AcademicDiscovery)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else { return nil }
            let payload = try JSONDecoder().decode(UnpaywallResponse.self, from: data)
            let pdfURL = firstNonEmpty([payload.bestOALocation?.urlForPDF])
            let landingURL = firstNonEmpty([payload.bestOALocation?.url, payload.doiURL, normalizeDOI(work.doi), work.primaryLocation?.landingPageURL])
            let oaURL = firstNonEmpty([payload.bestOALocation?.url, payload.bestOALocation?.urlForPDF, work.openAccess?.oaURL])
            let isOA = payload.isOA ?? !(pdfURL ?? "").isEmpty || !(oaURL ?? "").isEmpty

            guard isOA || !(landingURL ?? "").isEmpty else { return nil }

            return OpenAlexWork(
                id: work.id,
                displayName: work.displayName,
                publicationYear: work.publicationYear,
                citedByCount: work.citedByCount,
                doi: work.doi,
                type: work.type,
                citedByAPIURL: work.citedByAPIURL,
                referencedWorks: work.referencedWorks,
                abstractInvertedIndex: work.abstractInvertedIndex,
                openAccess: OpenAccess(
                    isOA: isOA || work.openAccess?.isOA == true,
                    oaURL: oaURL
                ),
                primaryLocation: PrimaryLocation(
                    landingPageURL: landingURL,
                    pdfURL: firstNonEmpty([pdfURL, work.primaryLocation?.pdfURL])
                )
            )
        } catch {
            return nil
        }
    }

    private func buildUnpaywallURL(for doiURL: String, email: String) -> URL? {
        guard let encoded = doiURL.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        var components = URLComponents(string: "https://api.unpaywall.org/v2/\(encoded)")
        components?.queryItems = [URLQueryItem(name: "email", value: email)]
        return components?.url
    }

    private func unpaywallEmail() -> String? {
        let value = ProcessInfo.processInfo.environment["ATLAS_UNPAYWALL_EMAIL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
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
        switch resolveSourceLabel(work) {
        case "Semantic Scholar":
            score += 0.01
        case "PubMed", "arXiv":
            score += 0.02
        default:
            break
        }

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
            return "Full text PDF"
        }
        if work.openAccess?.isOA == true || !(work.openAccess?.oaURL ?? "").isEmpty {
            return "Full text"
        }
        if !(work.doi ?? "").isEmpty {
            return "DOI / abstract"
        }
        return "Abstract only"
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
        sourceMode: ResearchSourceMode,
        candidateCount: Int,
        top: [ScoredWork]
    ) -> String {
        var lines: [String] = []
        lines.append("Academic discovery: scanned \(candidateCount) direct academic results and ranked top \(top.count) by abstract relevance + evidence strength.")
        lines.append("Domain mode: \(domainModeLabel(domainMode)).")
        lines.append("Methodology mode: \(methodologyFilterLabel(methodologyFilter)).")
        lines.append("Source mode: \(sourceModeLabel(sourceMode)).")
        lines.append("")
        lines.append("Comparative Matrix (Top Matches)")
        lines.append("# | Year | Citations | Source | Method | Sample | Outcome | Access")
        for (index, item) in top.enumerated() {
            let year = item.work.publicationYear.map(String.init) ?? "n/a"
            let citations = item.work.citedByCount.map(String.init) ?? "0"
            lines.append("\(index + 1) | \(year) | \(citations) | \(resolveSourceLabel(item.work)) | \(item.methodLabel) | \(item.sampleLabel) | \(item.outcomeLabel) | \(item.accessLabel)")
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

    private func buildNextAction(top: [ScoredWork], methodologyFilter: MethodologyFilter, domainMode: ResearchDomainMode, sourceMode: ResearchSourceMode) -> String {
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
        return "Open top 3 links, compare \(methodHint), then cross-check across \(sourceModeLabel(sourceMode).lowercased()) and run citation snowballing from the top seed. Validate \(domainHint). Start with: \(seedLink)"
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

    private func noResultOutput(for prompt: String, methodologyFilter: MethodologyFilter, domainMode: ResearchDomainMode, sourceMode: ResearchSourceMode) -> LocalReasoningOutput {
        let hints = topicExplorerHints(for: prompt, mode: domainMode)
        let hintLine: String
        if hints.isEmpty {
            hintLine = "Try adding target population, timeframe, and one methodology requirement."
        } else {
            hintLine = "Try one of these sub-queries: \(hints.joined(separator: " | "))"
        }

        return LocalReasoningOutput(
            model: "atlas-academic-discovery-v3",
            summary: "Academic discovery did not find strong matches under \(methodologyFilterLabel(methodologyFilter)) mode (\(domainModeLabel(domainMode)), \(sourceModeLabel(sourceMode))). \(hintLine)",
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

    private func detectSourceMode(_ prompt: String) -> ResearchSourceMode {
        let lower = prompt.lowercased()
        if containsAny(lower, needles: ["semantic scholar", "semanticscholar", "s2 only", "source: semantic"]) {
            return .semanticScholar
        }
        if containsAny(lower, needles: ["pubmed only", "source: pubmed", "pubmed mode"]) {
            return .pubMed
        }
        if containsAny(lower, needles: ["arxiv only", "source: arxiv", "arxiv mode"]) {
            return .arxiv
        }
        if containsAny(lower, needles: ["openalex only", "source: openalex"]) {
            return .openAlex
        }
        if containsAny(lower, needles: ["cross-check", "cross check", "compare sources", "multi-source", "multi source"]) {
            return .crossCheck
        }
        return .auto
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

    private func sourceModeLabel(_ mode: ResearchSourceMode) -> String {
        switch mode {
        case .auto:
            return "Auto (OpenAlex + Semantic Scholar + PubMed/arXiv when relevant)"
        case .openAlex:
            return "OpenAlex only"
        case .semanticScholar:
            return "Semantic Scholar only"
        case .pubMed:
            return "PubMed only"
        case .arxiv:
            return "arXiv only"
        case .crossCheck:
            return "Cross-check (OpenAlex + Semantic Scholar + PubMed/arXiv when relevant)"
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

    private func resolveSourceLabel(_ work: OpenAlexWork) -> String {
        let id = (work.id ?? "").lowercased()
        let link = (resolveBestLink(work) ?? "").lowercased()
        if id.contains("pubmed.ncbi.nlm.nih.gov") || link.contains("pubmed.ncbi.nlm.nih.gov") {
            return "PubMed"
        }
        if id.contains("arxiv.org") || link.contains("arxiv.org") {
            return "arXiv"
        }
        if id.contains("semanticscholar") || link.contains("semanticscholar") {
            return "Semantic Scholar"
        }
        return "OpenAlex"
    }

    private func makeInvertedIndex(from abstract: String?) -> [String: [Int]]? {
        guard let abstract = abstract?.trimmingCharacters(in: .whitespacesAndNewlines), !abstract.isEmpty else {
            return nil
        }
        let tokens = abstract.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }
        var index: [String: [Int]] = [:]
        for (position, token) in tokens.enumerated() {
            index[token, default: []].append(position)
        }
        return index
    }

    private func regexMatches(pattern: String, in text: String, captureGroup: Int? = nil) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            let targetRange = captureGroup.flatMap { $0 < match.numberOfRanges ? match.range(at: $0) : nil } ?? match.range(at: 0)
            guard let swiftRange = Range(targetRange, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    private func decodeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
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
