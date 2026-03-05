using AtlasMasaWindows.Models;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AtlasMasaWindows.Services;

public sealed class OnDeviceLlmClient
{
    private static readonly string[] DefaultModelCatalog =
    [
        "llama3.1:70b",
        "qwen2.5:32b",
        "deepseek-r1:14b",
        "qwen2.5:7b",
        "llama3.2:latest"
    ];

    private readonly bool _enabled;
    private readonly Uri? _endpoint;
    private readonly string _preferredModel;
    private readonly IReadOnlyList<string> _modelCatalog;
    private readonly SystemPerformanceProfile _performance;
    private readonly RustReasoningBridge _rustBridge;
    private readonly HttpClient _httpClient;
    private string _lastRuntimeFailure = "none";
    private string _activeRuntimeModel = "llama3.2:latest";
    private string _activeReasoningMode = "standard";
    private string _activePolicyStatus = "Rust policy unavailable.";
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public bool Enabled => _enabled && _endpoint is not null;
    public string LastRuntimeFailure => _lastRuntimeFailure;
    public string RuntimeEndpointLabel => _endpoint?.ToString() ?? "invalid-endpoint";
    public string RuntimeModel => _activeRuntimeModel;
    public string RuntimePolicyStatus => _activePolicyStatus;
    public string RuntimeModelCatalog => string.Join(", ", _modelCatalog);

    public string StatusLine
    {
        get
        {
            if (!_enabled)
            {
                return "Local LLM bridge disabled (`ATLAS_LOCAL_LLM_ENABLED=false`).";
            }
            if (_endpoint is null)
            {
                return "Local LLM bridge misconfigured (invalid or unsafe endpoint).";
            }
            return $"Local LLM bridge enabled: {_endpoint.Host}{_endpoint.AbsolutePath} · model policy {_preferredModel} · active {RuntimeModel} ({_activeReasoningMode}) · catalog {_modelCatalog.Count} models · rust policy {(_rustBridge.Enabled ? "on" : "off")}.";
        }
    }

    public string RuntimeFailureHint()
    {
        if (!_enabled)
        {
            return "Local LLM is disabled. Set ATLAS_LOCAL_LLM_ENABLED=true to enable.";
        }
        if (_endpoint is null)
        {
            return "Local LLM endpoint is invalid or blocked. Use localhost/127.0.0.1 with /v1/chat/completions.";
        }
        if (_lastRuntimeFailure is "none")
        {
            return $"Local LLM runtime healthy at {RuntimeEndpointLabel} (model {RuntimeModel}, mode {_activeReasoningMode}).";
        }
        if (_lastRuntimeFailure.StartsWith("http_", StringComparison.Ordinal))
        {
            return $"Endpoint {RuntimeEndpointLabel} returned {_lastRuntimeFailure}. Ensure Ollama is running and the endpoint is OpenAI-compatible.";
        }
        if (_lastRuntimeFailure is "empty_content")
        {
            return $"No completion content returned from {RuntimeEndpointLabel} using model `{RuntimeModel}`. Verify model availability with `ollama list` and pull from catalog: {RuntimeModelCatalog}.";
        }
        if (_lastRuntimeFailure is "invalid_json_payload")
        {
            return $"Model response from {RuntimeEndpointLabel} was not valid JSON for Atlas parsing. Keep endpoint in OpenAI-compatible chat mode.";
        }
        if (_lastRuntimeFailure.StartsWith("exception:", StringComparison.Ordinal))
        {
            return $"Runtime exception from local LLM bridge ({_lastRuntimeFailure}). Check Ollama service health and local firewall policy.";
        }

        return $"Local LLM runtime failure: {_lastRuntimeFailure}. Endpoint: {RuntimeEndpointLabel}, model: {RuntimeModel}.";
    }

    public OnDeviceLlmClient(SystemPerformanceProfile performance)
    {
        _performance = performance;
        _rustBridge = new RustReasoningBridge();
        _enabled = ParseBool(Environment.GetEnvironmentVariable("ATLAS_LOCAL_LLM_ENABLED"), defaultValue: true);
        _preferredModel = SanitizeModel(Environment.GetEnvironmentVariable("ATLAS_LOCAL_LLM_MODEL"));
        _modelCatalog = ParseModelCatalog(Environment.GetEnvironmentVariable("ATLAS_LOCAL_LLM_MODEL_CATALOG"));
        _activeRuntimeModel = ResolveInitialActiveModel(_preferredModel, _modelCatalog);
        _endpoint = ParseEndpoint(Environment.GetEnvironmentVariable("ATLAS_LOCAL_LLM_ENDPOINT"));
        _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(75)
        };
        _httpClient.DefaultRequestHeaders.Accept.Clear();
        _httpClient.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        _httpClient.DefaultRequestHeaders.CacheControl = new CacheControlHeaderValue { NoStore = true };
    }

    public async Task<LocalReasoningOutput?> TryReasonAsync(
        string prompt,
        IReadOnlyList<NoteRecord> notes,
        AtlasSessionState session,
        IReadOnlyDictionary<string, string>? surveyAnswers = null,
        CancellationToken cancellationToken = default)
    {
        if (!Enabled || string.IsNullOrWhiteSpace(prompt))
        {
            _lastRuntimeFailure = "disabled_or_empty_prompt";
            return null;
        }

        var notesSnapshot = string.Join(
            "\n",
            notes.Take(16).Select(n => $"- {n.Title}: {TrimForDisplay(n.Content, 180)}"));
        var surveySnapshot = BuildSurveySnapshot(surveyAnswers);
        var instruction = $"""
            You are Atlas local reasoning engine.
            Return ONLY valid JSON:
            {{"summary":"...","next_action":"...","confidence":0.0}}
            Constraints:
            - summary <= 280 chars
            - next_action <= 180 chars
            - use prompt + memory context

            Prompt:
            {prompt}

            Session context:
            Daily priority: {session.DailyPriority}
            Mid-term goal: {session.MidTermGoal}
            Long-term vision: {session.LongTermVision}
            Current blockers: {session.Blockers}
            Mood/Energy: {session.Mood} / {session.Energy}

            Survey signals (full snapshot):
            {surveySnapshot}

            Notes:
            {notesSnapshot}
            """;
        var messages = new List<ChatMessage>
        {
            new() { Role = "system", Content = "Respond with concise operational output." },
            new() { Role = "user", Content = instruction }
        };
        var plan = await ResolveGenerationPlanAsync("queue_reasoning", 0.35, 420, 32, cancellationToken);

        foreach (var model in plan.ModelOrder)
        {
            _activeRuntimeModel = model;
            for (var pass = 0; pass < plan.AnalysisPasses; pass++)
            {
                var passTemperature = Math.Clamp(plan.Temperature + (pass * 0.04), 0.05, 0.95);
                var attempt = await SendChatAttemptAsync(
                    messages,
                    model,
                    passTemperature,
                    plan.MaxTokens,
                    plan.TimeoutSeconds,
                    cancellationToken);
                if (attempt.Content is null)
                {
                    _lastRuntimeFailure = attempt.Failure;
                    continue;
                }

                var parsed = ParseQueueJson(attempt.Content);
                if (parsed is null)
                {
                    _lastRuntimeFailure = "invalid_json_payload";
                    continue;
                }

                _lastRuntimeFailure = "none";
                return new LocalReasoningOutput
                {
                    Model = $"atlas-local-llm/{TrimForDisplay(model, 64)}",
                    Summary = TrimForDisplay(parsed.Summary, 420),
                    NextAction = TrimForDisplay(parsed.NextAction, 220),
                    Confidence = Math.Clamp(parsed.Confidence, 0.0, 1.0),
                    GeneratedAt = DateTimeOffset.UtcNow
                };
            }
        }

        return null;
    }

    public sealed class AdaptiveQuestionOutput
    {
        public string Question { get; init; } = string.Empty;
        public IReadOnlyList<string> Options { get; init; } = [];
    }

    public async Task<AdaptiveQuestionOutput?> TryAdaptiveBusinessQuestionAsync(
        string answeredSnapshot,
        string globalUserContext,
        CancellationToken cancellationToken = default)
    {
        if (!Enabled)
        {
            return null;
        }

        var instruction = $"""
            You are Atlas adaptive business interviewer running on Ollama.
            Generate exactly one multiple-choice question from user memory context.
            Output ONLY valid JSON:
            {{"question":"...","options":["...","...","...","..."]}}
            Constraints:
            - options must be 3 to 5 concise choices
            - each option <= 72 chars
            - question <= 180 chars
            - question should improve business execution precision now
            - avoid repeating previous answered questions

            PREVIOUS ANSWERS
            {answeredSnapshot}

            GLOBAL USER CONTEXT
            {globalUserContext}
            """;
        var messages = new List<ChatMessage>
        {
            new() { Role = "system", Content = "Return only valid JSON." },
            new() { Role = "user", Content = instruction }
        };
        var plan = await ResolveGenerationPlanAsync("adaptive_question", 0.2, 420, 20, cancellationToken);

        foreach (var model in plan.ModelOrder)
        {
            _activeRuntimeModel = model;
            for (var pass = 0; pass < plan.AnalysisPasses; pass++)
            {
                var passTemperature = Math.Clamp(plan.Temperature + (pass * 0.03), 0.05, 0.95);
                var attempt = await SendChatAttemptAsync(
                    messages,
                    model,
                    passTemperature,
                    plan.MaxTokens,
                    plan.TimeoutSeconds,
                    cancellationToken);
                if (attempt.Content is null)
                {
                    _lastRuntimeFailure = attempt.Failure;
                    continue;
                }

                var parsed = ParseAdaptiveQuestionJson(attempt.Content);
                if (parsed is not null)
                {
                    _lastRuntimeFailure = "none";
                    return parsed;
                }
                _lastRuntimeFailure = "invalid_json_payload";
            }
        }

        return null;
    }

    private sealed class ParsedQueue
    {
        public string Summary { get; init; } = string.Empty;
        public string NextAction { get; init; } = string.Empty;
        public double Confidence { get; init; } = 0.66;
    }

    private sealed class RuntimeGenerationPlan
    {
        public IReadOnlyList<string> ModelOrder { get; init; } = ["llama3.2:latest"];
        public int AnalysisPasses { get; init; } = 1;
        public double Temperature { get; init; } = 0.22;
        public int MaxTokens { get; init; } = 900;
        public int TimeoutSeconds { get; init; } = 24;
        public string ReasoningMode { get; init; } = "standard";
        public string PolicyStatus { get; init; } = "Fallback policy.";
    }

    private readonly record struct ChatAttemptResult(string? Content, string Failure);

    private AdaptiveQuestionOutput? ParseAdaptiveQuestionJson(string raw)
    {
        foreach (var candidate in JsonCandidates(raw))
        {
            try
            {
                using var doc = JsonDocument.Parse(candidate);
                if (doc.RootElement.ValueKind != JsonValueKind.Object)
                {
                    continue;
                }

                var root = doc.RootElement;
                var question = GetString(root, "question");
                if (string.IsNullOrWhiteSpace(question))
                {
                    continue;
                }

                if (!root.TryGetProperty("options", out var optionsNode) ||
                    optionsNode.ValueKind != JsonValueKind.Array)
                {
                    continue;
                }

                var options = optionsNode
                    .EnumerateArray()
                    .Select(node => node.ValueKind == JsonValueKind.String ? (node.GetString() ?? string.Empty).Trim() : string.Empty)
                    .Where(text => text.Length > 0)
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .Take(5)
                    .ToList();
                if (options.Count < 3)
                {
                    continue;
                }

                return new AdaptiveQuestionOutput
                {
                    Question = TrimForDisplay(question, 180),
                    Options = options.Select(opt => TrimForDisplay(opt, 72)).ToList()
                };
            }
            catch
            {
                // try next candidate
            }
        }

        return null;
    }

    private ParsedQueue? ParseQueueJson(string raw)
    {
        foreach (var candidate in JsonCandidates(raw))
        {
            try
            {
                using var doc = JsonDocument.Parse(candidate);
                if (doc.RootElement.ValueKind != JsonValueKind.Object)
                {
                    continue;
                }

                var root = doc.RootElement;
                var summary = GetString(root, "summary");
                var nextAction = GetString(root, "next_action");
                if (string.IsNullOrWhiteSpace(nextAction))
                {
                    nextAction = GetString(root, "nextAction");
                }
                if (string.IsNullOrWhiteSpace(summary) || string.IsNullOrWhiteSpace(nextAction))
                {
                    continue;
                }

                var confidence = GetDouble(root, "confidence") ?? 0.66;
                return new ParsedQueue
                {
                    Summary = summary,
                    NextAction = nextAction,
                    Confidence = confidence
                };
            }
            catch
            {
                // try next candidate
            }
        }
        return null;
    }

    private async Task<RuntimeGenerationPlan> ResolveGenerationPlanAsync(
        string task,
        double fallbackTemperature,
        int fallbackMaxTokens,
        int fallbackTimeoutSeconds,
        CancellationToken cancellationToken)
    {
        var fallback = BuildFallbackPlan(task, fallbackTemperature, fallbackMaxTokens, fallbackTimeoutSeconds);
        if (!_rustBridge.Enabled)
        {
            _activeReasoningMode = fallback.ReasoningMode;
            _activePolicyStatus = fallback.PolicyStatus;
            return fallback;
        }

        var rustPolicy = await _rustBridge.TrySelectPolicyAsync(
            platform: "windows",
            task: task,
            cpuCores: _performance.CpuCores,
            memoryGb: _performance.PhysicalMemoryGb,
            highPerformance: _performance.HighPerformanceMode,
            preferredModel: _preferredModel,
            modelCatalog: _modelCatalog,
            cancellationToken: cancellationToken);

        if (rustPolicy is null)
        {
            _activeReasoningMode = fallback.ReasoningMode;
            _activePolicyStatus = fallback.PolicyStatus;
            return fallback;
        }

        var modelOrder = MergeModelOrder(
            rustPolicy.SelectedModel,
            rustPolicy.FallbackModels,
            _preferredModel,
            _modelCatalog);

        var plan = new RuntimeGenerationPlan
        {
            ModelOrder = modelOrder,
            AnalysisPasses = Math.Clamp(rustPolicy.AnalysisPasses, 1, 6),
            Temperature = Math.Clamp(rustPolicy.Temperature, 0.0, 0.95),
            MaxTokens = Math.Clamp(rustPolicy.MaxTokens, 320, 4096),
            TimeoutSeconds = Math.Clamp(rustPolicy.TimeoutSeconds, 8, 180),
            ReasoningMode = string.IsNullOrWhiteSpace(rustPolicy.ReasoningMode) ? "standard" : rustPolicy.ReasoningMode,
            PolicyStatus = string.IsNullOrWhiteSpace(rustPolicy.StatusLine)
                ? $"Rust policy selected {rustPolicy.SelectedModel}."
                : rustPolicy.StatusLine
        };

        if (task.Equals("adaptive_question", StringComparison.OrdinalIgnoreCase))
        {
            plan.AnalysisPasses = Math.Min(plan.AnalysisPasses, 2);
            plan.MaxTokens = Math.Min(plan.MaxTokens, 720);
        }

        _activeReasoningMode = plan.ReasoningMode;
        _activePolicyStatus = plan.PolicyStatus;
        return plan;
    }

    private RuntimeGenerationPlan BuildFallbackPlan(
        string task,
        double fallbackTemperature,
        int fallbackMaxTokens,
        int fallbackTimeoutSeconds)
    {
        var lowTier = _performance.PhysicalMemoryGb < 12 || _performance.CpuCores < 8;
        var mode = lowTier ? "fast" : _performance.HighPerformanceMode ? "deep" : "standard";
        var passes = mode switch
        {
            "deep" => 3,
            "standard" => 2,
            _ => 1
        };
        var maxTokens = mode switch
        {
            "deep" => Math.Max(fallbackMaxTokens, 1200),
            "standard" => Math.Max(fallbackMaxTokens, 900),
            _ => fallbackMaxTokens
        };
        var timeout = mode switch
        {
            "deep" => Math.Max(fallbackTimeoutSeconds, 34),
            "standard" => Math.Max(fallbackTimeoutSeconds, 24),
            _ => fallbackTimeoutSeconds
        };
        if (task.Equals("adaptive_question", StringComparison.OrdinalIgnoreCase))
        {
            passes = 1;
            maxTokens = Math.Min(maxTokens, 680);
        }

        return new RuntimeGenerationPlan
        {
            ModelOrder = MergeModelOrder(null, null, _preferredModel, _modelCatalog),
            AnalysisPasses = passes,
            Temperature = Math.Clamp(fallbackTemperature, 0.0, 0.95),
            MaxTokens = Math.Clamp(maxTokens, 320, 4096),
            TimeoutSeconds = Math.Clamp(timeout, 8, 180),
            ReasoningMode = mode,
            PolicyStatus = $"Fallback policy ({mode}) based on hardware tier {_performance.Label}."
        };
    }

    private async Task<ChatAttemptResult> SendChatAttemptAsync(
        IReadOnlyList<ChatMessage> messages,
        string model,
        double temperature,
        int maxTokens,
        int timeoutSeconds,
        CancellationToken cancellationToken)
    {
        var payload = new ChatRequest
        {
            Model = model,
            Messages = messages.ToList(),
            Temperature = Math.Clamp(temperature, 0.0, 0.95),
            MaxTokens = Math.Clamp(maxTokens, 220, 4096),
            Stream = false
        };
        var raw = JsonSerializer.Serialize(payload, _jsonOptions);
        using var request = new HttpRequestMessage(HttpMethod.Post, _endpoint)
        {
            Content = new StringContent(raw, Encoding.UTF8, "application/json")
        };
        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutCts.CancelAfter(TimeSpan.FromSeconds(Math.Clamp(timeoutSeconds, 8, 180)));

        try
        {
            using var response = await _httpClient.SendAsync(request, timeoutCts.Token);
            if (!response.IsSuccessStatusCode)
            {
                return new ChatAttemptResult(null, $"http_{(int)response.StatusCode}");
            }

            var body = await response.Content.ReadAsStringAsync(timeoutCts.Token);
            var envelope = JsonSerializer.Deserialize<ChatResponse>(body, _jsonOptions);
            var content =
                envelope?.Choices?.FirstOrDefault()?.Message?.Content?.Trim()
                ?? envelope?.Choices?.FirstOrDefault()?.Text?.Trim();
            if (string.IsNullOrWhiteSpace(content))
            {
                return new ChatAttemptResult(null, "empty_content");
            }
            return new ChatAttemptResult(content, "none");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return new ChatAttemptResult(null, "timeout");
        }
        catch (Exception ex)
        {
            return new ChatAttemptResult(null, $"exception:{ex.GetType().Name}");
        }
    }

    private static IReadOnlyList<string> ParseModelCatalog(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return DefaultModelCatalog.ToList();
        }

        var parsed = raw
            .Split([',', ';', '|', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .Select(item => item.Trim())
            .Where(item => item.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (parsed.Count == 0)
        {
            return DefaultModelCatalog.ToList();
        }
        return parsed;
    }

    private static string ResolveInitialActiveModel(string preferredModel, IReadOnlyList<string> catalog)
    {
        if (!string.IsNullOrWhiteSpace(preferredModel) && !preferredModel.Equals("auto", StringComparison.OrdinalIgnoreCase))
        {
            return preferredModel;
        }
        return catalog.FirstOrDefault() ?? "llama3.2:latest";
    }

    private static IReadOnlyList<string> MergeModelOrder(
        string? selectedModel,
        IReadOnlyList<string>? fallbackModels,
        string preferredModel,
        IReadOnlyList<string> catalog)
    {
        var ordered = new List<string>();
        void Add(string? model)
        {
            if (string.IsNullOrWhiteSpace(model))
            {
                return;
            }
            var clean = model.Trim();
            if (!ordered.Any(existing => existing.Equals(clean, StringComparison.OrdinalIgnoreCase)))
            {
                ordered.Add(clean);
            }
        }

        if (!string.IsNullOrWhiteSpace(preferredModel) && !preferredModel.Equals("auto", StringComparison.OrdinalIgnoreCase))
        {
            Add(preferredModel);
        }
        Add(selectedModel);
        if (fallbackModels is not null)
        {
            foreach (var fallback in fallbackModels)
            {
                Add(fallback);
            }
        }
        foreach (var entry in catalog)
        {
            Add(entry);
        }

        if (ordered.Count == 0)
        {
            ordered.Add("llama3.2:latest");
        }
        return ordered;
    }

    private static string GetString(JsonElement root, string key)
    {
        if (!root.TryGetProperty(key, out var node))
        {
            return string.Empty;
        }
        return node.ValueKind == JsonValueKind.String ? node.GetString()?.Trim() ?? string.Empty : string.Empty;
    }

    private static double? GetDouble(JsonElement root, string key)
    {
        if (!root.TryGetProperty(key, out var node))
        {
            return null;
        }
        return node.ValueKind switch
        {
            JsonValueKind.Number when node.TryGetDouble(out var value) => value,
            JsonValueKind.String when double.TryParse(node.GetString(), out var parsed) => parsed,
            _ => null
        };
    }

    private static List<string> JsonCandidates(string raw)
    {
        var trimmed = raw.Trim();
        var candidates = new List<string> { trimmed };

        var firstFence = trimmed.IndexOf("```", StringComparison.Ordinal);
        if (firstFence >= 0)
        {
            var secondFence = trimmed.IndexOf("```", firstFence + 3, StringComparison.Ordinal);
            if (secondFence > firstFence)
            {
                var fenced = trimmed[(firstFence + 3)..secondFence].Trim();
                if (fenced.StartsWith("json", StringComparison.OrdinalIgnoreCase))
                {
                    fenced = fenced[4..].Trim();
                }
                if (!string.IsNullOrWhiteSpace(fenced))
                {
                    candidates.Add(fenced);
                }
            }
        }

        var objectBlock = ExtractBalanced(trimmed, '{', '}');
        if (!string.IsNullOrWhiteSpace(objectBlock))
        {
            candidates.Add(objectBlock);
        }

        var arrayBlock = ExtractBalanced(trimmed, '[', ']');
        if (!string.IsNullOrWhiteSpace(arrayBlock))
        {
            candidates.Add(arrayBlock);
        }

        return candidates;
    }

    private static string? ExtractBalanced(string text, char open, char close)
    {
        var depth = 0;
        var start = -1;
        var inString = false;
        var escaped = false;

        for (var i = 0; i < text.Length; i++)
        {
            var ch = text[i];

            if (inString)
            {
                if (escaped)
                {
                    escaped = false;
                    continue;
                }
                if (ch == '\\')
                {
                    escaped = true;
                    continue;
                }
                if (ch == '"')
                {
                    inString = false;
                }
                continue;
            }

            if (ch == '"')
            {
                inString = true;
                continue;
            }

            if (ch == open)
            {
                if (depth == 0)
                {
                    start = i;
                }
                depth++;
            }
            else if (ch == close && depth > 0)
            {
                depth--;
                if (depth == 0 && start >= 0)
                {
                    return text[start..(i + 1)];
                }
            }
        }

        return null;
    }

    private static Uri? ParseEndpoint(string? raw)
    {
        var candidate = string.IsNullOrWhiteSpace(raw)
            ? "http://127.0.0.1:11434/v1/chat/completions"
            : raw.Trim();
        if (!Uri.TryCreate(candidate, UriKind.Absolute, out var uri))
        {
            return null;
        }
        if (!IsEndpointAllowed(uri))
        {
            return null;
        }
        if (string.IsNullOrWhiteSpace(uri.AbsolutePath) || uri.AbsolutePath == "/")
        {
            var builder = new UriBuilder(uri)
            {
                Path = "/v1/chat/completions"
            };
            uri = builder.Uri;
        }
        return uri;
    }

    private static bool IsEndpointAllowed(Uri uri)
    {
        if (uri.Scheme.Equals("https", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }
        if (uri.Scheme.Equals("http", StringComparison.OrdinalIgnoreCase))
        {
            return uri.Host.Equals("127.0.0.1", StringComparison.OrdinalIgnoreCase)
                || uri.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase);
        }
        return false;
    }

    private static bool ParseBool(string? value, bool defaultValue)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return defaultValue;
        }
        var normalized = value.Trim().ToLowerInvariant();
        return normalized switch
        {
            "1" => true,
            "0" => false,
            "true" => true,
            "false" => false,
            "yes" => true,
            "no" => false,
            _ => defaultValue
        };
    }

    private static string SanitizeModel(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "auto";
        }
        return value.Trim();
    }

    private static string BuildSurveySnapshot(IReadOnlyDictionary<string, string>? surveyAnswers)
    {
        if (surveyAnswers is null || surveyAnswers.Count == 0)
        {
            return "- none yet";
        }

        var snapshot = string.Join(
            " | ",
            surveyAnswers
                .OrderBy(entry => entry.Key, StringComparer.Ordinal)
                .Select(entry => $"{entry.Key}={TrimForDisplay(entry.Value, 56)}"));
        return TrimForDisplay(snapshot, 1800);
    }

    private static string TrimForDisplay(string value, int maxChars)
    {
        var normalized = value
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n')
            .Trim();
        if (normalized.Length <= maxChars)
        {
            return normalized;
        }
        return normalized[..Math.Max(0, maxChars)].Trim();
    }

    private sealed class ChatRequest
    {
        [JsonPropertyName("model")]
        public string Model { get; set; } = string.Empty;
        [JsonPropertyName("messages")]
        public List<ChatMessage> Messages { get; set; } = [];
        [JsonPropertyName("temperature")]
        public double Temperature { get; set; }
        [JsonPropertyName("max_tokens")]
        public int MaxTokens { get; set; }
        [JsonPropertyName("stream")]
        public bool Stream { get; set; }
    }

    private sealed class ChatMessage
    {
        [JsonPropertyName("role")]
        public string Role { get; set; } = string.Empty;
        [JsonPropertyName("content")]
        public string Content { get; set; } = string.Empty;
    }

    private sealed class ChatResponse
    {
        [JsonPropertyName("choices")]
        public List<ChatChoice>? Choices { get; set; }
    }

    private sealed class ChatChoice
    {
        [JsonPropertyName("message")]
        public ChatMessageResponse? Message { get; set; }
        [JsonPropertyName("text")]
        public string? Text { get; set; }
    }

    private sealed class ChatMessageResponse
    {
        [JsonPropertyName("role")]
        public string? Role { get; set; }
        [JsonPropertyName("content")]
        public string? Content { get; set; }
    }
}
