using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace AtlasMasaWindows.Services;

public sealed class AcademicResearchService
{
    private enum MethodologyFilter
    {
        Any,
        MetaOrSystematic,
        RandomizedControlledTrial,
        HighEvidence
    }

    private enum ResearchSourceMode
    {
        Auto,
        OpenAlex,
        SemanticScholar,
        PubMed,
        Arxiv,
        CrossCheck
    }

    private enum ResearchDomainMode
    {
        General,
        Biomedical,
        ComputerScience
    }

    public sealed class AcademicDiscoveryResult
    {
        public string Summary { get; init; } = string.Empty;
        public string NextAction { get; init; } = string.Empty;
        public double Confidence { get; init; } = 0.7;
    }

    private static readonly HashSet<string> Stopwords =
    [
        "the", "and", "for", "with", "that", "this", "from", "have", "has", "were", "was", "what", "when", "where",
        "which", "will", "would", "could", "should", "into", "about", "your", "you", "our", "their", "they", "them",
        "than", "then", "there", "here", "while", "also", "after", "before", "study", "studies", "paper", "papers",
        "research", "find", "better", "best", "analysis"
    ];

    private static readonly string[] ResearchSignals =
    [
        "research paper", "research papers", "paper", "papers", "academic", "journal", "literature review",
        "systematic review", "meta-analysis", "meta analysis", "randomized controlled trial", "rct",
        "doi", "pubmed", "arxiv", "semantic scholar", "openalex", "citation", "citations",
        "clinical trial", "evidence", "peer reviewed", "peer-reviewed"
    ];

    private readonly HttpClient _httpClient;
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public AcademicResearchService(HttpClient? httpClient = null)
    {
        _httpClient = httpClient ?? new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(18)
        };

        if (!_httpClient.DefaultRequestHeaders.Accept.Any(header => header.MediaType == "application/json"))
        {
            _httpClient.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        }

        if (_httpClient.DefaultRequestHeaders.CacheControl is null)
        {
            _httpClient.DefaultRequestHeaders.CacheControl = new CacheControlHeaderValue { NoStore = true };
        }

        if (_httpClient.DefaultRequestHeaders.UserAgent.Count == 0)
        {
            _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("AtlasMasaWindows/1.0 (AcademicDiscovery)");
        }
    }

    public bool LooksLikeResearchPrompt(string prompt)
    {
        var lower = (prompt ?? string.Empty).ToLowerInvariant();
        if (lower.Length < 16)
        {
            return false;
        }

        return ResearchSignals.Any(lower.Contains);
    }

    public async Task<AcademicDiscoveryResult?> TryDiscoverAsync(string prompt, CancellationToken cancellationToken = default)
    {
        var normalizedPrompt = NormalizePrompt(prompt);
        if (!LooksLikeResearchPrompt(normalizedPrompt))
        {
            return null;
        }

        var methodologyFilter = DetectMethodologyFilter(normalizedPrompt);
        var domainMode = DetectResearchDomainMode(normalizedPrompt);
        var sourceMode = DetectSourceMode(normalizedPrompt);
        var searchQuery = BuildSearchQuery(normalizedPrompt);
        if (searchQuery.Length < 3)
        {
            return null;
        }

        var works = await FetchCandidatesAsync(searchQuery, domainMode, sourceMode, cancellationToken);
        if (works.Count == 0)
        {
            return BuildNoResultsPayload(normalizedPrompt, methodologyFilter, domainMode, sourceMode);
        }

        var queryTokens = Tokenize(searchQuery);
        if (queryTokens.Count == 0)
        {
            return null;
        }

        var scored = works
            .Select(work => ScoreWork(work, queryTokens, methodologyFilter, domainMode))
            .Where(candidate => candidate.Score > 0.14)
            .OrderByDescending(candidate => candidate.Score)
            .ThenByDescending(candidate => candidate.Work.CitedByCount ?? 0)
            .Take(10)
            .ToList();

        if (scored.Count == 0)
        {
            return BuildNoResultsPayload(normalizedPrompt, methodologyFilter, domainMode, sourceMode);
        }

        var summary = BuildSummary(normalizedPrompt, methodologyFilter, domainMode, sourceMode, works.Count, scored);
        var nextAction = BuildNextAction(scored, methodologyFilter, domainMode, sourceMode);
        var confidence = Math.Clamp(scored.Average(item => item.Score), 0.58, 0.95);

        return new AcademicDiscoveryResult
        {
            Summary = Trim(summary, 2400),
            NextAction = Trim(nextAction, 280),
            Confidence = confidence
        };
    }

    private static string BuildSearchQuery(string prompt)
    {
        var cleaned = prompt;
        foreach (var token in new[] { "meta-analysis", "meta analysis", "systematic review", "randomized", "rct", "trial", "doi", "pdf", "citation" })
        {
            cleaned = Regex.Replace(cleaned, $@"\b{Regex.Escape(token)}\b", " ", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        }
        cleaned = CollapseWhitespace(cleaned);
        return Trim(cleaned, 180);
    }

    private async Task<List<OpenAlexWork>> FetchCandidatesAsync(
        string searchQuery,
        ResearchDomainMode domainMode,
        ResearchSourceMode sourceMode,
        CancellationToken cancellationToken)
    {
        var openAlexTask = FetchOpenAlexWorksAsync(searchQuery, sourceMode, cancellationToken);
        var semanticScholarTask = FetchSemanticScholarWorksAsync(searchQuery, domainMode, sourceMode, cancellationToken);
        var pubMedTask = FetchPubMedWorksAsync(searchQuery, domainMode, sourceMode, cancellationToken);
        var arxivTask = FetchArxivWorksAsync(searchQuery, domainMode, sourceMode, cancellationToken);
        await Task.WhenAll(openAlexTask, semanticScholarTask, pubMedTask, arxivTask);
        var deduped = DeduplicateWorks(openAlexTask.Result.Concat(semanticScholarTask.Result).Concat(pubMedTask.Result).Concat(arxivTask.Result).ToList());
        return await EnrichWorksWithUnpaywallAsync(deduped, cancellationToken);
    }

    private async Task<List<OpenAlexWork>> FetchOpenAlexWorksAsync(
        string searchQuery,
        ResearchSourceMode sourceMode,
        CancellationToken cancellationToken)
    {
        if (sourceMode is ResearchSourceMode.SemanticScholar or ResearchSourceMode.PubMed or ResearchSourceMode.Arxiv)
        {
            return [];
        }

        var encoded = Uri.EscapeDataString(searchQuery);
        var requestUri =
            $"https://api.openalex.org/works?search={encoded}&per-page=100&sort=relevance_score:desc&select=id,display_name,publication_year,cited_by_count,doi,type,abstract_inverted_index,open_access,primary_location,cited_by_api_url,referenced_works";

        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, requestUri);
            using var response = await _httpClient.SendAsync(request, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return [];
            }

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            return JsonSerializer.Deserialize<OpenAlexEnvelope>(body, _jsonOptions)?.Results ?? [];
        }
        catch
        {
            return [];
        }
    }

    private async Task<List<OpenAlexWork>> FetchSemanticScholarWorksAsync(
        string searchQuery,
        ResearchDomainMode domainMode,
        ResearchSourceMode sourceMode,
        CancellationToken cancellationToken)
    {
        if (sourceMode is ResearchSourceMode.OpenAlex or ResearchSourceMode.PubMed or ResearchSourceMode.Arxiv)
        {
            return [];
        }

        var encoded = Uri.EscapeDataString(searchQuery);
        var limit = domainMode == ResearchDomainMode.ComputerScience ? 30 : 20;
        var requestUri =
            $"https://api.semanticscholar.org/graph/v1/paper/search?query={encoded}&limit={limit}&fields=paperId,title,year,abstract,url,citationCount,publicationTypes,externalIds,openAccessPdf,referenceCount";

        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, requestUri);
            using var response = await _httpClient.SendAsync(request, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return [];
            }

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            var envelope = JsonSerializer.Deserialize<SemanticScholarEnvelope>(body, _jsonOptions);
            return (envelope?.Data ?? [])
                .Select(MapSemanticScholarPaper)
                .ToList();
        }
        catch
        {
            return [];
        }
    }

    private async Task<List<OpenAlexWork>> FetchPubMedWorksAsync(
        string searchQuery,
        ResearchDomainMode domainMode,
        ResearchSourceMode sourceMode,
        CancellationToken cancellationToken)
    {
        if (!ShouldFetchPubMed(domainMode, sourceMode))
        {
            return [];
        }

        var encoded = Uri.EscapeDataString(searchQuery);
        var searchUri =
            $"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&retmode=json&retmax=12&sort=relevance&term={encoded}";

        try
        {
            using var searchRequest = new HttpRequestMessage(HttpMethod.Get, searchUri);
            using var searchResponse = await _httpClient.SendAsync(searchRequest, cancellationToken);
            if (!searchResponse.IsSuccessStatusCode)
            {
                return [];
            }

            var searchBody = await searchResponse.Content.ReadAsStringAsync(cancellationToken);
            var envelope = JsonSerializer.Deserialize<PubMedSearchEnvelope>(searchBody, _jsonOptions);
            var ids = envelope?.SearchResult.IdList?.Take(12).ToList() ?? [];
            if (ids.Count == 0)
            {
                return [];
            }

            var fetchUri =
                $"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&retmode=xml&id={string.Join(",", ids)}";
            using var fetchRequest = new HttpRequestMessage(HttpMethod.Get, fetchUri);
            using var fetchResponse = await _httpClient.SendAsync(fetchRequest, cancellationToken);
            if (!fetchResponse.IsSuccessStatusCode)
            {
                return [];
            }

            var fetchBody = await fetchResponse.Content.ReadAsStringAsync(cancellationToken);
            return ParsePubMedArticles(fetchBody);
        }
        catch
        {
            return [];
        }
    }

    private async Task<List<OpenAlexWork>> FetchArxivWorksAsync(
        string searchQuery,
        ResearchDomainMode domainMode,
        ResearchSourceMode sourceMode,
        CancellationToken cancellationToken)
    {
        if (!ShouldFetchArxiv(domainMode, sourceMode))
        {
            return [];
        }

        var encoded = Uri.EscapeDataString($"all:{searchQuery}");
        var requestUri =
            $"https://export.arxiv.org/api/query?search_query={encoded}&start=0&max_results=20&sortBy=relevance&sortOrder=descending";

        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, requestUri);
            using var response = await _httpClient.SendAsync(request, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return [];
            }

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            return ParseArxivEntries(body);
        }
        catch
        {
            return [];
        }
    }

    private static OpenAlexWork MapSemanticScholarPaper(SemanticScholarPaper paper)
    {
        return new OpenAlexWork
        {
            Id = paper.Url ?? (string.IsNullOrWhiteSpace(paper.PaperId) ? null : $"https://www.semanticscholar.org/paper/{paper.PaperId}"),
            DisplayName = paper.Title,
            PublicationYear = paper.Year,
            CitedByCount = paper.CitationCount,
            Doi = paper.ExternalIds?.Doi,
            Type = paper.PublicationTypes?.FirstOrDefault(),
            CitedByApiUrl = null,
            ReferencedWorks = [],
            AbstractInvertedIndex = MakeInvertedIndex(paper.Abstract),
            OpenAccess = new OpenAccessWire
            {
                IsOa = !string.IsNullOrWhiteSpace(paper.OpenAccessPdf?.Url),
                OaUrl = paper.OpenAccessPdf?.Url
            },
            PrimaryLocation = new PrimaryLocationWire
            {
                LandingPageUrl = paper.Url,
                PdfUrl = paper.OpenAccessPdf?.Url
            }
        };
    }

    private static List<OpenAlexWork> DeduplicateWorks(List<OpenAlexWork> works)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var deduped = new List<OpenAlexWork>();
        foreach (var work in works)
        {
            var title = work.DisplayName?.Trim().ToLowerInvariant() ?? string.Empty;
            var year = work.PublicationYear?.ToString() ?? "n/a";
            var doi = NormalizeDoi(work.Doi) ?? string.Empty;
            var key = !string.IsNullOrWhiteSpace(doi) ? doi : $"{title}|{year}";
            if (string.IsNullOrWhiteSpace(key) || !seen.Add(key))
            {
                continue;
            }
            deduped.Add(work);
        }
        return deduped;
    }

    private static MethodologyFilter DetectMethodologyFilter(string prompt)
    {
        var lower = prompt.ToLowerInvariant();
        if (ContainsAny(lower, "meta-analysis", "meta analysis", "systematic review"))
        {
            return MethodologyFilter.MetaOrSystematic;
        }
        if (ContainsAny(lower, "randomized controlled trial", "randomized", "rct", "controlled trial"))
        {
            return MethodologyFilter.RandomizedControlledTrial;
        }
        if (ContainsAny(lower, "high evidence", "strong evidence", "evidence quality", "methodology"))
        {
            return MethodologyFilter.HighEvidence;
        }
        return MethodologyFilter.Any;
    }

    private static ResearchSourceMode DetectSourceMode(string prompt)
    {
        var lower = prompt.ToLowerInvariant();
        if (ContainsAny(lower, "semantic scholar", "semanticscholar", "s2 only", "source: semantic"))
        {
            return ResearchSourceMode.SemanticScholar;
        }
        if (ContainsAny(lower, "pubmed only", "source: pubmed", "pubmed mode"))
        {
            return ResearchSourceMode.PubMed;
        }
        if (ContainsAny(lower, "arxiv only", "source: arxiv", "arxiv mode"))
        {
            return ResearchSourceMode.Arxiv;
        }
        if (ContainsAny(lower, "openalex only", "source: openalex"))
        {
            return ResearchSourceMode.OpenAlex;
        }
        if (ContainsAny(lower, "cross-check", "cross check", "compare sources", "multi-source", "multi source"))
        {
            return ResearchSourceMode.CrossCheck;
        }
        return ResearchSourceMode.Auto;
    }

    private static ResearchDomainMode DetectResearchDomainMode(string prompt)
    {
        var lower = prompt.ToLowerInvariant();
        if (ContainsAny(lower, "pubmed", "clinical", "medical", "medicine", "biomedical", "patient", "therapy", "health"))
        {
            return ResearchDomainMode.Biomedical;
        }
        if (ContainsAny(lower, "arxiv", "machine learning", "deep learning", "llm", "nlp", "computer vision", "benchmark", "algorithm"))
        {
            return ResearchDomainMode.ComputerScience;
        }
        return ResearchDomainMode.General;
    }

    private static string BuildSummary(
        string prompt,
        MethodologyFilter methodologyFilter,
        ResearchDomainMode domainMode,
        ResearchSourceMode sourceMode,
        int candidateCount,
        IReadOnlyList<ScoredWork> scored)
    {
        var builder = new StringBuilder();
        builder.AppendLine($"Academic discovery: scanned {candidateCount} direct academic results and ranked the top {scored.Count} by abstract relevance + evidence strength.");
        builder.AppendLine($"Domain mode: {DomainModeLabel(domainMode)}.");
        builder.AppendLine($"Methodology mode: {MethodologyFilterLabel(methodologyFilter)}.");
        builder.AppendLine($"Source mode: {SourceModeLabel(sourceMode)}.");
        builder.AppendLine();
        builder.AppendLine("Comparative Matrix (Top Matches)");
        builder.AppendLine("# | Year | Citations | Source | Method | Sample | Outcome | Access");

        for (var index = 0; index < scored.Count; index++)
        {
            var item = scored[index];
            var year = item.Work.PublicationYear?.ToString() ?? "n/a";
            var citations = item.Work.CitedByCount?.ToString() ?? "0";
            builder.AppendLine($"{index + 1} | {year} | {citations} | {ResolveSourceLabel(item.Work)} | {item.MethodLabel} | {item.SampleLabel} | {item.OutcomeLabel} | {item.AccessLabel}");
        }

        builder.AppendLine();
        builder.AppendLine("Direct Sources (anti-hallucination links)");
        foreach (var (item, rank) in scored.Take(6).Select((entry, idx) => (entry, idx + 1)))
        {
            var title = Trim(item.Work.DisplayName ?? "Untitled work", 120);
            var source = item.BestLink ?? item.DoiLink ?? item.Work.Id ?? "no-link";
            builder.AppendLine($"{rank}. {title} ({item.Work.PublicationYear?.ToString() ?? "n/a"}) -> {source}");
        }

        var top = scored[0];
        builder.AppendLine();
        builder.AppendLine("Citation Snowball");
        if (!string.IsNullOrWhiteSpace(top.Work.CitedByApiUrl))
        {
            builder.AppendLine($"Forward citations API: {top.Work.CitedByApiUrl}");
        }
        builder.AppendLine($"Backward references available: {top.BackwardReferenceCount}");
        foreach (var reference in top.Work.ReferencedWorks?.Take(8) ?? [])
        {
            builder.AppendLine($"- {NormalizeOpenAlexReference(reference)}");
        }

        builder.AppendLine();
        builder.AppendLine(BuildConsensusLine(scored));

        var topicExplorer = BuildTopicExplorerHints(prompt, domainMode);
        if (topicExplorer.Count > 0)
        {
            builder.AppendLine();
            builder.AppendLine("Topic Explorer");
            foreach (var suggestion in topicExplorer)
            {
                builder.AppendLine($"- {suggestion}");
            }
        }

        return builder.ToString().Trim();
    }

    private static string BuildNextAction(IReadOnlyList<ScoredWork> scored, MethodologyFilter filter, ResearchDomainMode domainMode, ResearchSourceMode sourceMode)
    {
        var first = scored.FirstOrDefault();
        if (first is null)
        {
            return "Broaden the query, then rerun with a clearer target population, outcome, and method filter.";
        }

        var methodHint = filter switch
        {
            MethodologyFilter.MetaOrSystematic => "meta-analysis/systematic review quality",
            MethodologyFilter.RandomizedControlledTrial => "RCT protocol quality and sample design",
            MethodologyFilter.HighEvidence => "highest-evidence hierarchy",
            _ => "method and sample quality"
        };

        var domainHint = domainMode switch
        {
            ResearchDomainMode.Biomedical => "clinical population and intervention",
            ResearchDomainMode.ComputerScience => "benchmark, dataset, and metric",
            _ => "population, method, and measured outcome"
        };

        var topLink = first.BestLink ?? first.DoiLink ?? first.Work.Id ?? "top source";
        return $"Open top 3 links, compare {methodHint}, then cross-check across {SourceModeLabel(sourceMode).ToLowerInvariant()} and run citation snowballing from the top seed. Validate {domainHint}. Start with: {topLink}";
    }

    private static AcademicDiscoveryResult BuildNoResultsPayload(string prompt, MethodologyFilter filter, ResearchDomainMode mode, ResearchSourceMode sourceMode)
    {
        var hints = BuildTopicExplorerHints(prompt, mode);
        var hintText = hints.Count == 0
            ? "Try adding target population, timeframe, and one methodology requirement."
            : $"Try one of these sub-queries: {string.Join(" | ", hints)}";

        return new AcademicDiscoveryResult
        {
            Summary = $"Academic discovery did not find strong matches for this query under {MethodologyFilterLabel(filter)} mode ({DomainModeLabel(mode)}, {SourceModeLabel(sourceMode)}). {hintText}",
            NextAction = "Broaden the query, remove one strict constraint, and rerun.",
            Confidence = 0.52
        };
    }

    private static HashSet<string> Tokenize(string text)
    {
        return text
            .ToLowerInvariant()
            .Split([' ', '\n', '\t', '.', ',', ';', ':', '!', '?', '(', ')', '[', ']', '{', '}', '/', '\\', '-', '_', '"', '\''], StringSplitOptions.RemoveEmptyEntries)
            .Select(token => token.Trim())
            .Where(token => token.Length >= 3 && !Stopwords.Contains(token))
            .ToHashSet(StringComparer.Ordinal);
    }

    private static ScoredWork ScoreWork(
        OpenAlexWork work,
        HashSet<string> queryTokens,
        MethodologyFilter methodologyFilter,
        ResearchDomainMode domainMode)
    {
        var title = work.DisplayName ?? string.Empty;
        var abstractText = BuildAbstract(work.AbstractInvertedIndex);
        var corpus = $"{title} {abstractText}".ToLowerInvariant();

        var matchCount = queryTokens.Count(token => corpus.Contains(token, StringComparison.Ordinal));
        var overlap = matchCount / (double)Math.Max(4, queryTokens.Count);
        var titleBoost = queryTokens.Count(token => title.Contains(token, StringComparison.OrdinalIgnoreCase)) / (double)Math.Max(4, queryTokens.Count);
        var citationBoost = Math.Min(0.24, Math.Log10((work.CitedByCount ?? 0) + 1.0) / 6.2);
        var recencyBoost = work.PublicationYear switch
        {
            >= 2023 => 0.10,
            >= 2019 => 0.07,
            >= 2014 => 0.04,
            _ => 0.01
        };

        var evidenceBoost = ResolveEvidenceBoost(work.Type, corpus);
        var methodologyBoost = ResolveMethodologyBoost(methodologyFilter, corpus);
        var domainBoost = ResolveDomainBoost(domainMode, corpus);
        var sampleLabel = ExtractSampleLabel(corpus);
        var outcomeLabel = ExtractOutcomeLabel(corpus);
        var score = (overlap * 0.52) + (titleBoost * 0.16) + citationBoost + recencyBoost + evidenceBoost + methodologyBoost + domainBoost;
        if (sampleLabel != "n/a")
        {
            score += 0.02;
        }
        if (outcomeLabel is "Benefit" or "Adverse")
        {
            score += 0.01;
        }
        if (ResolveSourceLabel(work) == "Semantic Scholar")
        {
            score += 0.01;
        }
        else if (ResolveSourceLabel(work) is "PubMed" or "arXiv")
        {
            score += 0.02;
        }

        return new ScoredWork
        {
            Work = work,
            Score = score,
            MethodLabel = ResolveMethodLabel(work.Type, corpus),
            SampleLabel = sampleLabel,
            OutcomeLabel = outcomeLabel,
            AccessLabel = ResolveAccessLabel(work),
            DoiLink = NormalizeDoi(work.Doi),
            BestLink = ResolveBestLink(work),
            Abstract = abstractText,
            BackwardReferenceCount = work.ReferencedWorks?.Count ?? 0
        };
    }

    private static double ResolveEvidenceBoost(string? type, string corpus)
    {
        var lowerType = (type ?? string.Empty).ToLowerInvariant();
        if (corpus.Contains("meta-analysis", StringComparison.Ordinal) || corpus.Contains("systematic review", StringComparison.Ordinal))
        {
            return 0.18;
        }
        if (corpus.Contains("randomized", StringComparison.Ordinal) || corpus.Contains("controlled trial", StringComparison.Ordinal))
        {
            return 0.14;
        }
        if (corpus.Contains("cohort", StringComparison.Ordinal) || corpus.Contains("longitudinal", StringComparison.Ordinal))
        {
            return 0.09;
        }
        if (lowerType.Contains("review", StringComparison.Ordinal))
        {
            return 0.1;
        }
        return 0.03;
    }

    private static double ResolveMethodologyBoost(MethodologyFilter filter, string corpus)
    {
        return filter switch
        {
            MethodologyFilter.MetaOrSystematic =>
                (corpus.Contains("meta-analysis", StringComparison.Ordinal) || corpus.Contains("systematic review", StringComparison.Ordinal)) ? 0.22 : -0.14,
            MethodologyFilter.RandomizedControlledTrial =>
                (corpus.Contains("randomized", StringComparison.Ordinal) || corpus.Contains("controlled trial", StringComparison.Ordinal) || Regex.IsMatch(corpus, @"\brct\b", RegexOptions.CultureInvariant)) ? 0.22 : -0.14,
            MethodologyFilter.HighEvidence =>
                (corpus.Contains("meta-analysis", StringComparison.Ordinal) ||
                 corpus.Contains("systematic review", StringComparison.Ordinal) ||
                 corpus.Contains("randomized", StringComparison.Ordinal) ||
                 corpus.Contains("controlled trial", StringComparison.Ordinal)) ? 0.16 : -0.05,
            _ => 0.0
        };
    }

    private static double ResolveDomainBoost(ResearchDomainMode mode, string corpus)
    {
        return mode switch
        {
            ResearchDomainMode.Biomedical => ContainsAny(corpus, "patient", "clinical", "therapy", "disease", "health", "treatment") ? 0.08 : -0.02,
            ResearchDomainMode.ComputerScience => ContainsAny(corpus, "benchmark", "dataset", "model", "algorithm", "transformer", "accuracy") ? 0.08 : -0.02,
            _ => 0.0
        };
    }

    private static string ResolveMethodLabel(string? type, string corpus)
    {
        if (corpus.Contains("meta-analysis", StringComparison.Ordinal) || corpus.Contains("systematic review", StringComparison.Ordinal))
        {
            return "Meta/Systematic";
        }
        if (corpus.Contains("randomized", StringComparison.Ordinal) || corpus.Contains("controlled trial", StringComparison.Ordinal) || Regex.IsMatch(corpus, @"\brct\b", RegexOptions.CultureInvariant))
        {
            return "RCT";
        }
        if (corpus.Contains("cohort", StringComparison.Ordinal) || corpus.Contains("longitudinal", StringComparison.Ordinal))
        {
            return "Cohort";
        }

        var lowerType = (type ?? string.Empty).ToLowerInvariant();
        if (lowerType.Contains("review", StringComparison.Ordinal))
        {
            return "Review";
        }
        if (lowerType.Contains("article", StringComparison.Ordinal))
        {
            return "Article";
        }
        return "Unspecified";
    }

    private static string ExtractSampleLabel(string corpus)
    {
        var nEquals = Regex.Match(corpus, @"\bn\s*[=:]\s*(\d{2,7})\b", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        if (nEquals.Success)
        {
            return $"N={nEquals.Groups[1].Value}";
        }

        var participants = Regex.Match(corpus, @"\b(\d{2,7})\s+(participants|patients|subjects|adults|children)\b", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        if (participants.Success)
        {
            return $"N~{participants.Groups[1].Value}";
        }

        return "n/a";
    }

    private static string ExtractOutcomeLabel(string corpus)
    {
        if (ContainsAny(corpus, "no significant", "not significant", "mixed results", "inconclusive", "heterogeneity"))
        {
            return "Mixed";
        }
        if (ContainsAny(corpus, "increase risk", "adverse", "harm", "worse", "toxicity"))
        {
            return "Adverse";
        }
        if (ContainsAny(corpus, "improve", "effective", "benefit", "reduced", "increase", "positive"))
        {
            return "Benefit";
        }
        return "Neutral";
    }

    private static string ResolveAccessLabel(OpenAlexWork work)
    {
        if (!string.IsNullOrWhiteSpace(work.PrimaryLocation?.PdfUrl))
        {
            return "Full text PDF";
        }
        if (work.OpenAccess?.IsOa is true || !string.IsNullOrWhiteSpace(work.OpenAccess?.OaUrl))
        {
            return "Full text";
        }
        if (!string.IsNullOrWhiteSpace(work.Doi))
        {
            return "DOI / abstract";
        }
        return "Abstract only";
    }

    private async Task<List<OpenAlexWork>> EnrichWorksWithUnpaywallAsync(List<OpenAlexWork> works, CancellationToken cancellationToken)
    {
        var email = Environment.GetEnvironmentVariable("ATLAS_UNPAYWALL_EMAIL")?.Trim();
        if (string.IsNullOrWhiteSpace(email))
        {
            return works;
        }

        var eligible = works
            .Select((work, index) => new { work, index })
            .Where(item =>
                item.index < 12 &&
                !string.IsNullOrWhiteSpace(item.work.Doi) &&
                string.IsNullOrWhiteSpace(item.work.PrimaryLocation?.PdfUrl) &&
                string.IsNullOrWhiteSpace(item.work.OpenAccess?.OaUrl) &&
                item.work.OpenAccess?.IsOa is not true)
            .ToList();

        if (eligible.Count == 0)
        {
            return works;
        }

        var updates = await Task.WhenAll(eligible.Select(async item =>
        {
            var enriched = await FetchUnpaywallEnrichmentAsync(item.work, email!, cancellationToken);
            return (item.index, enriched);
        }));

        foreach (var (index, enriched) in updates)
        {
            if (enriched is not null)
            {
                works[index] = enriched;
            }
        }

        return works;
    }

    private async Task<OpenAlexWork?> FetchUnpaywallEnrichmentAsync(OpenAlexWork work, string email, CancellationToken cancellationToken)
    {
        var doi = NormalizeDoi(work.Doi);
        if (string.IsNullOrWhiteSpace(doi))
        {
            return null;
        }

        var requestUri = $"https://api.unpaywall.org/v2/{Uri.EscapeDataString(doi)}?email={Uri.EscapeDataString(email)}";

        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, requestUri);
            using var response = await _httpClient.SendAsync(request, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return null;
            }

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            var payload = JsonSerializer.Deserialize<UnpaywallResponse>(body, _jsonOptions);
            var pdfUrl = FirstNonEmpty(payload?.BestOaLocation?.UrlForPdf);
            var landingUrl = FirstNonEmpty(payload?.BestOaLocation?.Url, payload?.DoiUrl, doi, work.PrimaryLocation?.LandingPageUrl);
            var oaUrl = FirstNonEmpty(payload?.BestOaLocation?.Url, payload?.BestOaLocation?.UrlForPdf, work.OpenAccess?.OaUrl);
            var isOa = payload?.IsOa ?? (!string.IsNullOrWhiteSpace(pdfUrl) || !string.IsNullOrWhiteSpace(oaUrl));

            if (!isOa && string.IsNullOrWhiteSpace(landingUrl))
            {
                return null;
            }

            return new OpenAlexWork
            {
                Id = work.Id,
                DisplayName = work.DisplayName,
                PublicationYear = work.PublicationYear,
                CitedByCount = work.CitedByCount,
                Doi = work.Doi,
                Type = work.Type,
                CitedByApiUrl = work.CitedByApiUrl,
                ReferencedWorks = work.ReferencedWorks,
                AbstractInvertedIndex = work.AbstractInvertedIndex,
                OpenAccess = new OpenAccessWire
                {
                    IsOa = isOa || work.OpenAccess?.IsOa is true,
                    OaUrl = oaUrl
                },
                PrimaryLocation = new PrimaryLocationWire
                {
                    LandingPageUrl = landingUrl,
                    PdfUrl = FirstNonEmpty(pdfUrl, work.PrimaryLocation?.PdfUrl)
                }
            };
        }
        catch
        {
            return null;
        }
    }

    private static string? ResolveBestLink(OpenAlexWork work)
    {
        return FirstNonEmpty(
            work.PrimaryLocation?.PdfUrl,
            work.OpenAccess?.OaUrl,
            work.PrimaryLocation?.LandingPageUrl,
            NormalizeDoi(work.Doi),
            work.Id);
    }

    private static string BuildConsensusLine(IReadOnlyList<ScoredWork> scored)
    {
        var supportive = 0;
        var mixed = 0;
        var cautious = 0;

        foreach (var item in scored)
        {
            var text = $"{item.Work.DisplayName} {item.Abstract}".ToLowerInvariant();
            if (ContainsAny(text, "no significant", "not significant", "mixed results", "inconclusive", "heterogeneity"))
            {
                mixed++;
                continue;
            }
            if (ContainsAny(text, "improve", "effective", "benefit", "reduced", "increase", "positive"))
            {
                supportive++;
                continue;
            }
            cautious++;
        }

        return $"Consensus snapshot: supportive={supportive}, mixed/inconclusive={mixed}, cautious/neutral={cautious}.";
    }

    private static List<string> BuildTopicExplorerHints(string prompt, ResearchDomainMode mode)
    {
        var tokens = Tokenize(prompt);
        if (tokens.Count > 4)
        {
            return [];
        }

        var lower = prompt.ToLowerInvariant();
        if (ContainsAny(lower, "ai", "llm", "machine learning") || mode == ResearchDomainMode.ComputerScience)
        {
            return
            [
                "Benchmark + dataset + metric comparison",
                "Ablation and failure-mode analysis",
                "Latency/cost/quality tradeoff studies"
            ];
        }
        if (ContainsAny(lower, "health", "medical", "clinical") || mode == ResearchDomainMode.Biomedical)
        {
            return
            [
                "Population + intervention + outcome framing",
                "RCT and meta-analysis evidence split",
                "Safety/adverse-event incidence comparison"
            ];
        }
        if (ContainsAny(lower, "education", "learning", "school"))
        {
            return
            [
                "Personalized learning outcomes in K-12",
                "Academic integrity + AI policy outcomes",
                "Teacher workload effects from AI copilots"
            ];
        }
        if (ContainsAny(lower, "business", "revenue", "sales", "growth"))
        {
            return
            [
                "Customer acquisition strategy meta-analyses",
                "Retention intervention effect sizes",
                "Pricing strategy evidence in SaaS and services"
            ];
        }

        return
        [
            "Target population + intervention + outcome",
            "Comparative method (A/B or treatment/control)",
            "Time horizon and measurable endpoint"
        ];
    }

    private static string BuildAbstract(Dictionary<string, List<int>>? invertedIndex)
    {
        if (invertedIndex is null || invertedIndex.Count == 0)
        {
            return string.Empty;
        }

        var maxPosition = -1;
        foreach (var positions in invertedIndex.Values)
        {
            foreach (var position in positions)
            {
                if (position > maxPosition)
                {
                    maxPosition = position;
                }
            }
        }

        if (maxPosition < 0 || maxPosition > 4096)
        {
            return string.Empty;
        }

        var ordered = new string[maxPosition + 1];
        foreach (var (token, positions) in invertedIndex)
        {
            foreach (var position in positions)
            {
                if (position >= 0 && position < ordered.Length && string.IsNullOrWhiteSpace(ordered[position]))
                {
                    ordered[position] = token;
                }
            }
        }

        var abstractText = string.Join(" ", ordered.Where(token => !string.IsNullOrWhiteSpace(token)));
        return Trim(CollapseWhitespace(abstractText), 4000);
    }

    private static string MethodologyFilterLabel(MethodologyFilter filter)
    {
        return filter switch
        {
            MethodologyFilter.MetaOrSystematic => "Meta-analysis / Systematic review prioritized",
            MethodologyFilter.RandomizedControlledTrial => "Randomized controlled trials prioritized",
            MethodologyFilter.HighEvidence => "High-evidence papers prioritized",
            _ => "General evidence mix"
        };
    }

    private static string DomainModeLabel(ResearchDomainMode mode)
    {
        return mode switch
        {
            ResearchDomainMode.Biomedical => "Biomedical (PubMed-like evidence focus)",
            ResearchDomainMode.ComputerScience => "Computer Science / AI (arXiv-like benchmark focus)",
            _ => "General"
        };
    }

    private static string SourceModeLabel(ResearchSourceMode mode)
    {
        return mode switch
        {
            ResearchSourceMode.OpenAlex => "OpenAlex only",
            ResearchSourceMode.SemanticScholar => "Semantic Scholar only",
            ResearchSourceMode.PubMed => "PubMed only",
            ResearchSourceMode.Arxiv => "arXiv only",
            ResearchSourceMode.CrossCheck => "Cross-check (OpenAlex + Semantic Scholar + PubMed/arXiv when relevant)",
            _ => "Auto (OpenAlex + Semantic Scholar + PubMed/arXiv when relevant)"
        };
    }

    private static string NormalizeOpenAlexReference(string value)
    {
        var trimmed = value.Trim();
        if (string.IsNullOrWhiteSpace(trimmed))
        {
            return string.Empty;
        }
        if (trimmed.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || trimmed.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            return trimmed;
        }
        if (trimmed.StartsWith("W", StringComparison.OrdinalIgnoreCase))
        {
            return $"https://openalex.org/{trimmed}";
        }
        return trimmed;
    }

    private static string ResolveSourceLabel(OpenAlexWork work)
    {
        var id = work.Id?.ToLowerInvariant() ?? string.Empty;
        var link = ResolveBestLink(work)?.ToLowerInvariant() ?? string.Empty;
        if (id.Contains("pubmed.ncbi.nlm.nih.gov", StringComparison.Ordinal) || link.Contains("pubmed.ncbi.nlm.nih.gov", StringComparison.Ordinal))
        {
            return "PubMed";
        }
        if (id.Contains("arxiv.org", StringComparison.Ordinal) || link.Contains("arxiv.org", StringComparison.Ordinal))
        {
            return "arXiv";
        }
        return id.Contains("semanticscholar", StringComparison.Ordinal) || link.Contains("semanticscholar", StringComparison.Ordinal)
            ? "Semantic Scholar"
            : "OpenAlex";
    }

    private static string? NormalizeDoi(string? rawDoi)
    {
        var trimmed = rawDoi?.Trim();
        if (string.IsNullOrWhiteSpace(trimmed))
        {
            return null;
        }
        if (trimmed.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
            trimmed.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            return trimmed;
        }
        trimmed = trimmed.Replace("doi:", string.Empty, StringComparison.OrdinalIgnoreCase).Trim();
        return $"https://doi.org/{trimmed}";
    }

    private static string NormalizePrompt(string input)
    {
        return CollapseWhitespace((input ?? string.Empty).Replace('\r', ' ').Replace('\n', ' ')).Trim();
    }

    private static string CollapseWhitespace(string value)
    {
        return Regex.Replace(value, @"\s+", " ", RegexOptions.CultureInvariant);
    }

    private static Dictionary<string, List<int>>? MakeInvertedIndex(string? abstractText)
    {
        if (string.IsNullOrWhiteSpace(abstractText))
        {
            return null;
        }

        var tokens = abstractText
            .Split([' ', '\n', '\t'], StringSplitOptions.RemoveEmptyEntries)
            .Select(token => token.Trim())
            .Where(token => token.Length > 0)
            .ToList();
        if (tokens.Count == 0)
        {
            return null;
        }

        var index = new Dictionary<string, List<int>>(StringComparer.Ordinal);
        for (var position = 0; position < tokens.Count; position++)
        {
            var token = tokens[position];
            if (!index.TryGetValue(token, out var positions))
            {
                positions = [];
                index[token] = positions;
            }
            positions.Add(position);
        }
        return index;
    }

    private static bool ShouldFetchPubMed(ResearchDomainMode domainMode, ResearchSourceMode sourceMode)
    {
        return sourceMode switch
        {
            ResearchSourceMode.PubMed => true,
            ResearchSourceMode.Auto or ResearchSourceMode.CrossCheck => domainMode == ResearchDomainMode.Biomedical,
            _ => false
        };
    }

    private static bool ShouldFetchArxiv(ResearchDomainMode domainMode, ResearchSourceMode sourceMode)
    {
        return sourceMode switch
        {
            ResearchSourceMode.Arxiv => true,
            ResearchSourceMode.Auto or ResearchSourceMode.CrossCheck => domainMode == ResearchDomainMode.ComputerScience,
            _ => false
        };
    }

    private static List<OpenAlexWork> ParsePubMedArticles(string xml)
    {
        try
        {
            var document = XDocument.Parse(xml);
            return document
                .Descendants("PubmedArticle")
                .Select(article =>
                {
                    var title = CollapseWhitespace(HtmlToText((article.Descendants("ArticleTitle").FirstOrDefault()?.Value) ?? string.Empty));
                    if (string.IsNullOrWhiteSpace(title))
                    {
                        return null;
                    }

                    var pmid = article.Descendants("PMID").FirstOrDefault()?.Value?.Trim();
                    var yearText =
                        article.Descendants("PubDate").Descendants("Year").FirstOrDefault()?.Value?.Trim() ??
                        article.Descendants("ArticleDate").Descendants("Year").FirstOrDefault()?.Value?.Trim();
                    var abstractText = CollapseWhitespace(string.Join(" ", article.Descendants("AbstractText").Select(node => HtmlToText(node.Value))));
                    var doi = article
                        .Descendants("ArticleId")
                        .FirstOrDefault(node => string.Equals(node.Attribute("IdType")?.Value, "doi", StringComparison.OrdinalIgnoreCase))
                        ?.Value
                        ?.Trim();
                    var pubMedUrl = string.IsNullOrWhiteSpace(pmid) ? null : $"https://pubmed.ncbi.nlm.nih.gov/{pmid}/";

                    return new OpenAlexWork
                    {
                        Id = pubMedUrl,
                        DisplayName = title,
                        PublicationYear = int.TryParse(yearText, out var year) ? year : null,
                        CitedByCount = null,
                        Doi = doi,
                        Type = article.Descendants("PublicationType").Any(node => node.Value.Contains("Review", StringComparison.OrdinalIgnoreCase)) ? "review" : "article",
                        CitedByApiUrl = null,
                        ReferencedWorks = [],
                        AbstractInvertedIndex = MakeInvertedIndex(abstractText),
                        OpenAccess = new OpenAccessWire
                        {
                            IsOa = false,
                            OaUrl = null
                        },
                        PrimaryLocation = new PrimaryLocationWire
                        {
                            LandingPageUrl = pubMedUrl,
                            PdfUrl = null
                        }
                    };
                })
                .Where(work => work is not null)
                .Cast<OpenAlexWork>()
                .ToList();
        }
        catch
        {
            return [];
        }
    }

    private static List<OpenAlexWork> ParseArxivEntries(string xml)
    {
        try
        {
            var document = XDocument.Parse(xml);
            XNamespace atom = "http://www.w3.org/2005/Atom";
            XNamespace arxiv = "http://arxiv.org/schemas/atom";

            return document
                .Descendants(atom + "entry")
                .Select(entry =>
                {
                    var title = CollapseWhitespace(HtmlToText(entry.Element(atom + "title")?.Value ?? string.Empty));
                    if (string.IsNullOrWhiteSpace(title))
                    {
                        return null;
                    }

                    var summary = CollapseWhitespace(HtmlToText(entry.Element(atom + "summary")?.Value ?? string.Empty));
                    var id = entry.Element(atom + "id")?.Value?.Trim();
                    var published = entry.Element(atom + "published")?.Value?.Trim();
                    var year = int.TryParse(published?.Split('-').FirstOrDefault(), out var parsedYear) ? parsedYear : null;
                    var doi = entry.Element(arxiv + "doi")?.Value?.Trim();
                    var pdf = entry
                        .Elements(atom + "link")
                        .FirstOrDefault(node => string.Equals(node.Attribute("title")?.Value, "pdf", StringComparison.OrdinalIgnoreCase))
                        ?.Attribute("href")
                        ?.Value
                        ?.Trim();

                    return new OpenAlexWork
                    {
                        Id = id,
                        DisplayName = title,
                        PublicationYear = year,
                        CitedByCount = null,
                        Doi = doi,
                        Type = "preprint",
                        CitedByApiUrl = null,
                        ReferencedWorks = [],
                        AbstractInvertedIndex = MakeInvertedIndex(summary),
                        OpenAccess = new OpenAccessWire
                        {
                            IsOa = true,
                            OaUrl = pdf
                        },
                        PrimaryLocation = new PrimaryLocationWire
                        {
                            LandingPageUrl = id,
                            PdfUrl = pdf
                        }
                    };
                })
                .Where(work => work is not null)
                .Cast<OpenAlexWork>()
                .ToList();
        }
        catch
        {
            return [];
        }
    }

    private static string HtmlToText(string value)
    {
        return value
            .Replace("&lt;", "<", StringComparison.Ordinal)
            .Replace("&gt;", ">", StringComparison.Ordinal)
            .Replace("&amp;", "&", StringComparison.Ordinal)
            .Replace("&quot;", "\"", StringComparison.Ordinal)
            .Replace("&apos;", "'", StringComparison.Ordinal)
            .Replace("&#39;", "'", StringComparison.Ordinal);
    }

    private static bool ContainsAny(string text, params string[] signals)
    {
        return signals.Any(signal => text.Contains(signal, StringComparison.Ordinal));
    }

    private static string Trim(string value, int maxChars)
    {
        var clean = (value ?? string.Empty).Trim();
        if (clean.Length <= maxChars)
        {
            return clean;
        }
        return clean[..Math.Max(0, maxChars)].Trim();
    }

    private static string? FirstNonEmpty(params string?[] values)
    {
        foreach (var value in values)
        {
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value.Trim();
            }
        }
        return null;
    }

    private sealed class ScoredWork
    {
        public OpenAlexWork Work { get; init; } = new();
        public double Score { get; init; }
        public string MethodLabel { get; init; } = "Unspecified";
        public string SampleLabel { get; init; } = "n/a";
        public string OutcomeLabel { get; init; } = "Neutral";
        public string AccessLabel { get; init; } = "Abstract";
        public string? DoiLink { get; init; }
        public string? BestLink { get; init; }
        public string Abstract { get; init; } = string.Empty;
        public int BackwardReferenceCount { get; init; }
    }

    private sealed class OpenAlexEnvelope
    {
        [JsonPropertyName("results")]
        public List<OpenAlexWork> Results { get; init; } = [];
    }

    private sealed class SemanticScholarEnvelope
    {
        [JsonPropertyName("data")]
        public List<SemanticScholarPaper> Data { get; init; } = [];
    }

    private sealed class PubMedSearchEnvelope
    {
        [JsonPropertyName("esearchresult")]
        public PubMedSearchResult SearchResult { get; init; } = new();
    }

    private sealed class PubMedSearchResult
    {
        [JsonPropertyName("idlist")]
        public List<string> IdList { get; init; } = [];
    }

    private sealed class OpenAlexWork
    {
        [JsonPropertyName("id")]
        public string? Id { get; init; }

        [JsonPropertyName("display_name")]
        public string? DisplayName { get; init; }

        [JsonPropertyName("publication_year")]
        public int? PublicationYear { get; init; }

        [JsonPropertyName("cited_by_count")]
        public int? CitedByCount { get; init; }

        [JsonPropertyName("doi")]
        public string? Doi { get; init; }

        [JsonPropertyName("type")]
        public string? Type { get; init; }

        [JsonPropertyName("cited_by_api_url")]
        public string? CitedByApiUrl { get; init; }

        [JsonPropertyName("referenced_works")]
        public List<string>? ReferencedWorks { get; init; }

        [JsonPropertyName("abstract_inverted_index")]
        public Dictionary<string, List<int>>? AbstractInvertedIndex { get; init; }

        [JsonPropertyName("open_access")]
        public OpenAccessWire? OpenAccess { get; init; }

        [JsonPropertyName("primary_location")]
        public PrimaryLocationWire? PrimaryLocation { get; init; }
    }

    private sealed class SemanticScholarPaper
    {
        [JsonPropertyName("paperId")]
        public string? PaperId { get; init; }

        [JsonPropertyName("title")]
        public string? Title { get; init; }

        [JsonPropertyName("year")]
        public int? Year { get; init; }

        [JsonPropertyName("citationCount")]
        public int? CitationCount { get; init; }

        [JsonPropertyName("abstract")]
        public string? Abstract { get; init; }

        [JsonPropertyName("url")]
        public string? Url { get; init; }

        [JsonPropertyName("openAccessPdf")]
        public SemanticScholarPdf? OpenAccessPdf { get; init; }

        [JsonPropertyName("externalIds")]
        public SemanticScholarExternalIds? ExternalIds { get; init; }

        [JsonPropertyName("publicationTypes")]
        public List<string>? PublicationTypes { get; init; }

        [JsonPropertyName("referenceCount")]
        public int? ReferenceCount { get; init; }
    }

    private sealed class SemanticScholarPdf
    {
        [JsonPropertyName("url")]
        public string? Url { get; init; }
    }

    private sealed class SemanticScholarExternalIds
    {
        [JsonPropertyName("DOI")]
        public string? Doi { get; init; }
    }

    private sealed class UnpaywallResponse
    {
        [JsonPropertyName("is_oa")]
        public bool? IsOa { get; init; }

        [JsonPropertyName("best_oa_location")]
        public UnpaywallLocation? BestOaLocation { get; init; }

        [JsonPropertyName("doi_url")]
        public string? DoiUrl { get; init; }
    }

    private sealed class UnpaywallLocation
    {
        [JsonPropertyName("url")]
        public string? Url { get; init; }

        [JsonPropertyName("url_for_pdf")]
        public string? UrlForPdf { get; init; }
    }

    private sealed class OpenAccessWire
    {
        [JsonPropertyName("is_oa")]
        public bool? IsOa { get; init; }

        [JsonPropertyName("oa_url")]
        public string? OaUrl { get; init; }
    }

    private sealed class PrimaryLocationWire
    {
        [JsonPropertyName("landing_page_url")]
        public string? LandingPageUrl { get; init; }

        [JsonPropertyName("pdf_url")]
        public string? PdfUrl { get; init; }
    }
}
