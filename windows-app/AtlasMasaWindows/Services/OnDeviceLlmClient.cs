using AtlasMasaWindows.Models;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Globalization;

namespace AtlasMasaWindows.Services;

public sealed class OnDeviceLlmClient
{
    private static readonly string[] DefaultModelCatalog =
    [
        "qwen2.5:32b",
        "deepseek-r1:14b",
        "llama3.1:70b",
        "qwen2.5:7b",
        "llama3.2:latest"
    ];

    private readonly bool _enabled;
    private readonly Uri? _endpoint;
    private readonly IReadOnlyList<string> _preferredModels;
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
    public IReadOnlyList<string> PreferredModels => _preferredModels;

    public sealed record RuntimeProvisioningUpdate(
        string StatusCode,
        string Status,
        string Detail,
        double Progress,
        bool Busy,
        bool Ready,
        long DownloadedBytes,
        long TotalBytes,
        int? EtaSeconds,
        string LastError);

    public sealed record RuntimeProvisioningResult(
        bool Ready,
        string StatusCode,
        string Status,
        string Detail,
        string LastError);

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
            return $"Endpoint {RuntimeEndpointLabel} returned {_lastRuntimeFailure}. Local model service may still be warming up.";
        }
        if (_lastRuntimeFailure is "empty_content")
        {
            return $"No completion content returned from {RuntimeEndpointLabel} using model `{RuntimeModel}`.";
        }
        if (_lastRuntimeFailure is "invalid_json_payload")
        {
            return $"Model response from {RuntimeEndpointLabel} was not valid JSON for Atlas parsing. Keep endpoint in OpenAI-compatible chat mode.";
        }
        if (_lastRuntimeFailure.StartsWith("exception:", StringComparison.Ordinal))
        {
            return $"Runtime exception from local LLM bridge ({_lastRuntimeFailure}).";
        }

        return $"Local LLM runtime failure: {_lastRuntimeFailure}. Endpoint: {RuntimeEndpointLabel}, model: {RuntimeModel}.";
    }

    public bool IsOllamaMissing() => string.IsNullOrWhiteSpace(ResolveOllamaBinaryPath());

    public OnDeviceLlmClient(SystemPerformanceProfile performance)
    {
        _performance = performance;
        _rustBridge = new RustReasoningBridge();
        _enabled = ParseBool(Environment.GetEnvironmentVariable("ATLAS_LOCAL_LLM_ENABLED"), defaultValue: true);
        _preferredModels = ParsePreferredModels(Environment.GetEnvironmentVariable("ATLAS_LOCAL_LLM_MODEL"));
        _preferredModel = _preferredModels.FirstOrDefault() ?? "qwen2.5:7b";
        _modelCatalog = ParseModelCatalog(Environment.GetEnvironmentVariable("ATLAS_LOCAL_LLM_MODEL_CATALOG"));
        _activeRuntimeModel = ResolveInitialActiveModel(_preferredModel, _modelCatalog);
        _endpoint = ParseEndpoint(Environment.GetEnvironmentVariable("ATLAS_LOCAL_LLM_ENDPOINT"));
        _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(180)
        };
        _httpClient.DefaultRequestHeaders.Accept.Clear();
        _httpClient.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        _httpClient.DefaultRequestHeaders.CacheControl = new CacheControlHeaderValue { NoStore = true };
    }

    public async Task<RuntimeProvisioningResult> EnsureRuntimeReadyAsync(
        Action<RuntimeProvisioningUpdate>? onUpdate = null,
        CancellationToken cancellationToken = default)
    {
        void publish(
            string statusCode,
            string status,
            string detail,
            double progress,
            bool busy,
            bool ready,
            long downloaded = 0,
            long total = 0,
            int? eta = null,
            string lastError = "")
        {
            onUpdate?.Invoke(new RuntimeProvisioningUpdate(
                statusCode,
                status,
                detail,
                Math.Clamp(progress, 0.0, 1.0),
                busy,
                ready,
                Math.Max(0, downloaded),
                Math.Max(0, total),
                eta,
                lastError));
        }

        if (!Enabled || _endpoint is null)
        {
            publish("error", "Local AI setup blocked", "Runtime provisioning skipped (disabled or invalid endpoint).", 0.0, false, false, lastError: "Local AI provisioning requires a valid localhost endpoint.");
            return new RuntimeProvisioningResult(false, "error", "Local AI setup blocked", "disabled_or_invalid_endpoint", "Local AI provisioning requires a valid localhost endpoint.");
        }

        var host = _endpoint.Host.ToLowerInvariant();
        var isLoopback = host is "127.0.0.1" or "localhost";
        if (!isLoopback)
        {
            publish("error", "Local AI setup blocked", "Runtime provisioning skipped (non-local endpoint).", 0.0, false, false, lastError: "Local AI provisioning only supports localhost endpoints.");
            return new RuntimeProvisioningResult(false, "error", "Local AI setup blocked", "non_local_endpoint", "Local AI provisioning only supports localhost endpoints.");
        }

        publish("starting_runtime", "Checking local AI", "Verifying local model service availability.", 0.08, true, false);
        if (await IsRuntimeReadyForInferenceAsync(_preferredModel, timeoutSeconds: 4, cancellationToken))
        {
            publish("ready", "Local AI ready", $"Model {_preferredModel} is active.", 1.0, false, true);
            return new RuntimeProvisioningResult(true, "ready", "Local AI ready", "already_ready", string.Empty);
        }

        var ollamaPath = ResolveOllamaBinaryPath();
        if (string.IsNullOrWhiteSpace(ollamaPath))
        {
            publish("installing_runtime", "Install Local AI", "Ollama is not installed yet. Install it from BlackHaven to continue setup.", 0.0, false, false, lastError: "Ollama runtime is missing.");
            return new RuntimeProvisioningResult(false, "installing_runtime", "Install Local AI", "ollama_missing", "Ollama runtime is missing.");
        }

        if (!await IsRuntimeReachableAsync(timeoutSeconds: 2, cancellationToken))
        {
            publish("starting_runtime", "Starting local AI", "Launching Ollama local service.", 0.2, true, false);
            _ = TryStartOllamaServeProcess(ollamaPath);
            if (!await WaitForRuntimeReachableAsync(timeoutSeconds: 16, cancellationToken))
            {
                publish("degraded", "Local AI retrying", "Ollama service did not become reachable yet. BlackHaven will retry.", 0.0, false, false, lastError: "The local AI runtime did not become reachable.");
                return new RuntimeProvisioningResult(false, "degraded", "Local AI retrying", "ollama_service_unreachable", "The local AI runtime did not become reachable.");
            }
        }

        var modelsToEnsure = MergeModelOrder(null, null, _preferredModel, _preferredModels.Concat(_modelCatalog).ToList())
            .Take(Math.Max(1, _preferredModels.Count))
            .ToList();
        if (modelsToEnsure.Count == 0)
        {
            modelsToEnsure.Add("qwen2.5:7b");
        }

        var stageBase = 0.3;
        var stageSpan = 0.6 / Math.Max(1, modelsToEnsure.Count);
        for (var i = 0; i < modelsToEnsure.Count; i++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var model = modelsToEnsure[i];
            if (await OllamaHasModelAsync(model, ollamaPath, cancellationToken))
            {
                continue;
            }

            var stageStart = stageBase + (stageSpan * i);
            var stageEnd = stageStart + stageSpan;
            var pullSuccess = await PullOllamaModelWithProgressAsync(
                ollamaPath,
                model,
                timeoutSeconds: 2400,
                progress =>
                {
                    var staged = stageStart + ((stageEnd - stageStart) * progress.ProgressRatio);
                    publish(
                        "downloading_model",
                        "Downloading model",
                        progress.Detail,
                        staged,
                        true,
                        false,
                        progress.DownloadedBytes,
                        progress.TotalBytes,
                        progress.EtaSeconds);
                },
                cancellationToken);
            if (!pullSuccess)
            {
                publish("error", "Local AI needs attention", $"Model download failed for {model}.", 0.0, false, false, lastError: $"BlackHaven could not finish downloading {model}.");
                return new RuntimeProvisioningResult(false, "error", "Local AI needs attention", $"pull_failed:{model}", $"BlackHaven could not finish downloading {model}.");
            }
        }

        publish("warming_model", "Warming local AI", $"Running inference probe on {_preferredModel}.", 0.94, true, false);
        if (!await IsRuntimeReadyForInferenceAsync(_preferredModel, timeoutSeconds: 8, cancellationToken))
        {
            publish("degraded", "Local AI retrying", "Runtime endpoint is up but model inference is not ready yet.", 0.0, false, false, lastError: "The selected model is still warming up.");
            return new RuntimeProvisioningResult(false, "degraded", "Local AI retrying", "inference_not_ready", "The selected model is still warming up.");
        }

        publish("ready", "Local AI ready", $"Models ready: {string.Join(", ", modelsToEnsure)}.", 1.0, false, true);
        return new RuntimeProvisioningResult(true, "ready", "Local AI ready", "ok", string.Empty);
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
            notes.Take(_performance.UltraPerformanceMode ? 32 : _performance.HighPerformanceMode ? 24 : 16)
                .Select(n => $"- {n.Title}: {TrimForDisplay(n.Content, _performance.HighPerformanceMode ? 280 : 180)}"));
        var surveySnapshot = BuildSurveySnapshot(surveyAnswers);
        var instruction = $"""
            You are Atlas local reasoning engine.
            Return ONLY valid JSON:
            {{"summary":"...","next_action":"...","confidence":0.0}}
            Constraints:
            - summary <= 420 chars
            - next_action <= 220 chars
            - use prompt + memory context
            - compare multiple plausible options before choosing the best operational answer

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
        var plan = await ResolveGenerationPlanAsync("queue_reasoning", 0.28, 1200, 48, cancellationToken);

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
                    GeneratedAt = DateTimeOffset.UtcNow,
                    ReasoningSummary = BuildReasoningSummary(parsed.Summary, parsed.NextAction),
                    AlternativesConsidered = BuildAlternatives(parsed.NextAction),
                    Assumptions = BuildAssumptions(),
                    ConfidenceLabel = ConfidenceLabel(parsed.Confidence)
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
        var plan = await ResolveGenerationPlanAsync("adaptive_question", 0.18, 720, 24, cancellationToken);

        foreach (var model in plan.ModelOrder)
        {
            _activeRuntimeModel = model;
            for (var pass = 0; pass < plan.AnalysisPasses; pass++)
            {
                var passTemperature = Math.Clamp(plan.Temperature + (pass * 0.02), 0.05, 0.95);
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

    private static string BuildReasoningSummary(string summary, string nextAction)
    {
        var trimmedSummary = TrimForDisplay(summary, 160);
        var trimmedAction = TrimForDisplay(nextAction, 120);
        return $"Selected the clearest practical route, compared quick alternatives, and optimized for usable follow-through. Core direction: {trimmedSummary}. Immediate move: {trimmedAction}.";
    }

    private static List<string> BuildAlternatives(string nextAction)
    {
        var trimmedAction = TrimForDisplay(nextAction, 120);
        return
        [
            "Ask more diagnostic follow-up questions before recommending a move.",
            "Offer a broader multi-step strategy instead of the fastest practical path.",
            $"Delay action instead of moving on \"{trimmedAction}\" now."
        ];
    }

    private static List<string> BuildAssumptions()
    {
        return
        [
            "The current prompt, memory snapshot, and survey signals are enough to take a useful next step.",
            "A fast actionable answer is more valuable here than slower exhaustive analysis."
        ];
    }

    private static string ConfidenceLabel(double confidence) => Math.Clamp(confidence, 0.0, 1.0) switch
    {
        < 0.45 => "Low",
        < 0.72 => "Medium",
        < 0.9 => "High",
        _ => "Very High"
    };

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
            MaxTokens = Math.Clamp(rustPolicy.MaxTokens, 480, 8192),
            TimeoutSeconds = Math.Clamp(rustPolicy.TimeoutSeconds, 12, 240),
            ReasoningMode = string.IsNullOrWhiteSpace(rustPolicy.ReasoningMode) ? "standard" : rustPolicy.ReasoningMode,
            PolicyStatus = string.IsNullOrWhiteSpace(rustPolicy.StatusLine)
                ? $"Rust policy selected {rustPolicy.SelectedModel}."
                : rustPolicy.StatusLine
        };

        if (task.Equals("adaptive_question", StringComparison.OrdinalIgnoreCase))
        {
            plan.AnalysisPasses = Math.Min(plan.AnalysisPasses, 2);
            plan.MaxTokens = Math.Min(plan.MaxTokens, 960);
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
            "deep" => _performance.UltraPerformanceMode ? 5 : 4,
            "standard" => 2,
            _ => 1
        };
        var maxTokens = mode switch
        {
            "deep" => Math.Max(fallbackMaxTokens, _performance.UltraPerformanceMode ? 2600 : 1800),
            "standard" => Math.Max(fallbackMaxTokens, 1200),
            _ => fallbackMaxTokens
        };
        var timeout = mode switch
        {
            "deep" => Math.Max(fallbackTimeoutSeconds, _performance.UltraPerformanceMode ? 70 : 52),
            "standard" => Math.Max(fallbackTimeoutSeconds, 32),
            _ => fallbackTimeoutSeconds
        };
        if (task.Equals("adaptive_question", StringComparison.OrdinalIgnoreCase))
        {
            passes = Math.Min(passes, _performance.HighPerformanceMode ? 2 : 1);
            maxTokens = Math.Min(maxTokens, 960);
        }

        return new RuntimeGenerationPlan
        {
            ModelOrder = MergeModelOrder(null, null, _preferredModel, _modelCatalog),
            AnalysisPasses = passes,
            Temperature = Math.Clamp(fallbackTemperature, 0.0, 0.95),
            MaxTokens = Math.Clamp(maxTokens, 480, 8192),
            TimeoutSeconds = Math.Clamp(timeout, 12, 240),
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
            MaxTokens = Math.Clamp(maxTokens, 220, 8192),
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

    private static IReadOnlyList<string> ParsePreferredModels(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw) || raw.Trim().Equals("auto", StringComparison.OrdinalIgnoreCase))
        {
            return ["qwen2.5:7b", "deepseek-r1:14b"];
        }

        var parsed = raw
            .Split([',', ';', '|', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .Select(item => item.Trim())
            .Where(item => item.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (parsed.Count == 0)
        {
            return ["qwen2.5:7b", "deepseek-r1:14b"];
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

    private sealed record PullProgressSnapshot(
        string Detail,
        double ProgressRatio,
        long DownloadedBytes,
        long TotalBytes,
        int? EtaSeconds);

    private async Task<bool> IsRuntimeReachableAsync(int timeoutSeconds, CancellationToken cancellationToken)
    {
        if (_endpoint is null)
        {
            return false;
        }

        var probePaths = new[] { "/v1/models", "/api/tags", "/health", "/" };
        foreach (var path in probePaths)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var probeUri = new UriBuilder(_endpoint) { Path = path, Query = string.Empty }.Uri;
            using var request = new HttpRequestMessage(HttpMethod.Get, probeUri);
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(TimeSpan.FromSeconds(Math.Clamp(timeoutSeconds, 1, 10)));
            try
            {
                using var response = await _httpClient.SendAsync(request, cts.Token);
                if ((int)response.StatusCode is >= 200 and < 300)
                {
                    return true;
                }
            }
            catch
            {
                // continue probing
            }
        }
        return false;
    }

    private async Task<bool> WaitForRuntimeReachableAsync(int timeoutSeconds, CancellationToken cancellationToken)
    {
        var timeoutAt = DateTimeOffset.UtcNow.AddSeconds(Math.Clamp(timeoutSeconds, 2, 90));
        while (DateTimeOffset.UtcNow < timeoutAt)
        {
            if (await IsRuntimeReachableAsync(2, cancellationToken))
            {
                return true;
            }
            await Task.Delay(350, cancellationToken);
        }
        return false;
    }

    private async Task<bool> IsRuntimeReadyForInferenceAsync(string model, int timeoutSeconds, CancellationToken cancellationToken)
    {
        if (!await IsRuntimeReachableAsync(Math.Min(timeoutSeconds, 3), cancellationToken))
        {
            return false;
        }

        var probeMessages = new List<ChatMessage>
        {
            new() { Role = "system", Content = "Return only READY." },
            new() { Role = "user", Content = "Reply with exactly: READY" }
        };
        var attempt = await SendChatAttemptAsync(
            probeMessages,
            model,
            temperature: 0.0,
            maxTokens: 32,
            timeoutSeconds: Math.Clamp(timeoutSeconds, 4, 18),
            cancellationToken);
        return attempt.Content?.Contains("READY", StringComparison.OrdinalIgnoreCase) == true;
    }

    private static string? ResolveOllamaBinaryPath()
    {
        var env = Environment.GetEnvironmentVariable("ATLAS_OLLAMA_BIN");
        if (!string.IsNullOrWhiteSpace(env) && File.Exists(env.Trim()))
        {
            return env.Trim();
        }

        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var candidates = new[]
        {
            Path.Combine(localAppData, "Programs", "Ollama", "ollama.exe"),
            @"C:\Program Files\Ollama\ollama.exe",
            "ollama.exe"
        };
        return candidates.FirstOrDefault(path =>
            !string.IsNullOrWhiteSpace(path)
            && (path.Equals("ollama.exe", StringComparison.OrdinalIgnoreCase) || File.Exists(path)));
    }

    private static bool TryStartOllamaServeProcess(string ollamaBinaryPath)
    {
        try
        {
            var process = new System.Diagnostics.Process();
            process.StartInfo = new System.Diagnostics.ProcessStartInfo
            {
                FileName = ollamaBinaryPath,
                Arguments = "serve",
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = false,
                RedirectStandardError = false
            };
            process.Start();
            try
            {
                process.PriorityClass = System.Diagnostics.ProcessPriorityClass.High;
            }
            catch
            {
                // Priority elevation is opportunistic on Windows.
            }
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static async Task<(int ExitCode, string Output)> RunOllamaCommandAsync(
        string ollamaBinaryPath,
        string arguments,
        int timeoutSeconds,
        CancellationToken cancellationToken)
    {
        try
        {
            using var process = new System.Diagnostics.Process();
            process.StartInfo = new System.Diagnostics.ProcessStartInfo
            {
                FileName = ollamaBinaryPath,
                Arguments = arguments,
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            process.Start();

            var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeoutCts.CancelAfter(TimeSpan.FromSeconds(Math.Clamp(timeoutSeconds, 3, 7200)));
            await process.WaitForExitAsync(timeoutCts.Token);

            var output = await outputTask;
            var error = await errorTask;
            return (process.ExitCode, $"{output}\n{error}".Trim());
        }
        catch (OperationCanceledException)
        {
            return (-2, string.Empty);
        }
        catch
        {
            return (-1, string.Empty);
        }
    }

    private static async Task<bool> OllamaHasModelAsync(
        string model,
        string ollamaBinaryPath,
        CancellationToken cancellationToken)
    {
        var target = model.Trim().ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(target))
        {
            return false;
        }
        var result = await RunOllamaCommandAsync(ollamaBinaryPath, "list", 20, cancellationToken);
        if (result.ExitCode != 0)
        {
            return false;
        }
        var lines = result.Output
            .ToLowerInvariant()
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return lines.Any(line => line.StartsWith(target + " ", StringComparison.Ordinal) || line.Equals(target, StringComparison.Ordinal));
    }

    private static async Task<bool> PullOllamaModelWithProgressAsync(
        string ollamaBinaryPath,
        string model,
        int timeoutSeconds,
        Action<PullProgressSnapshot>? onProgress,
        CancellationToken cancellationToken)
    {
        var tempFile = Path.Combine(Path.GetTempPath(), $"atlas-ollama-pull-{Guid.NewGuid():N}.log");
        try
        {
            await File.WriteAllTextAsync(tempFile, string.Empty, cancellationToken);
            using var stream = new FileStream(tempFile, FileMode.Append, FileAccess.Write, FileShare.ReadWrite);
            using var writer = new StreamWriter(stream) { AutoFlush = true };
            using var process = new System.Diagnostics.Process();
            process.StartInfo = new System.Diagnostics.ProcessStartInfo
            {
                FileName = ollamaBinaryPath,
                Arguments = $"pull {model}",
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            process.OutputDataReceived += (_, args) =>
            {
                if (!string.IsNullOrWhiteSpace(args.Data))
                {
                    writer.WriteLine(args.Data);
                }
            };
            process.ErrorDataReceived += (_, args) =>
            {
                if (!string.IsNullOrWhiteSpace(args.Data))
                {
                    writer.WriteLine(args.Data);
                }
            };

            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            var timeoutAt = DateTimeOffset.UtcNow.AddSeconds(Math.Clamp(timeoutSeconds, 30, 7200));
            long latestDownloaded = 0;
            long latestTotal = 0;
            int? latestEta = null;
            string detail = $"Downloading {model}...";
            (DateTimeOffset Time, long Downloaded)? previousSample = null;

            while (!process.HasExited)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (DateTimeOffset.UtcNow >= timeoutAt)
                {
                    process.Kill(entireProcessTree: true);
                    return false;
                }

                var lines = (await File.ReadAllLinesAsync(tempFile, cancellationToken))
                    .Where(line => !string.IsNullOrWhiteSpace(line))
                    .ToArray();
                if (lines.Length > 0)
                {
                    detail = lines[^1].Length > 220 ? lines[^1][..220] : lines[^1];
                    foreach (var line in lines.TakeLast(20))
                    {
                        if (TryExtractByteProgress(line, out var downloaded, out var total))
                        {
                            latestDownloaded = Math.Max(latestDownloaded, downloaded);
                            latestTotal = Math.Max(latestTotal, total);
                        }
                    }
                }

                if (latestTotal > 0 && latestDownloaded > 0)
                {
                    var now = DateTimeOffset.UtcNow;
                    if (previousSample is { } sample && latestDownloaded > sample.Downloaded)
                    {
                        var elapsed = (now - sample.Time).TotalSeconds;
                        var delta = latestDownloaded - sample.Downloaded;
                        if (elapsed > 0.2 && delta > 0)
                        {
                            var bps = delta / elapsed;
                            var remaining = latestTotal - latestDownloaded;
                            latestEta = bps > 0 ? (int)Math.Round(remaining / bps) : null;
                        }
                    }
                    previousSample = (now, latestDownloaded);
                }

                var ratio = latestTotal > 0 ? (double)latestDownloaded / latestTotal : 0.0;
                onProgress?.Invoke(new PullProgressSnapshot(detail, Math.Clamp(ratio, 0.0, 1.0), latestDownloaded, latestTotal, latestEta));
                await Task.Delay(240, cancellationToken);
            }

            return process.ExitCode == 0;
        }
        finally
        {
            try { File.Delete(tempFile); } catch { }
        }
    }

    private static bool TryExtractByteProgress(string line, out long downloadedBytes, out long totalBytes)
    {
        downloadedBytes = 0;
        totalBytes = 0;
        if (string.IsNullOrWhiteSpace(line))
        {
            return false;
        }

        var match = System.Text.RegularExpressions.Regex.Match(
            line,
            @"(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB)\s*/\s*(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB)",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        if (!match.Success)
        {
            return false;
        }

        if (!double.TryParse(match.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var downloadedValue) ||
            !double.TryParse(match.Groups[3].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var totalValue))
        {
            return false;
        }

        downloadedBytes = ToBytes(downloadedValue, match.Groups[2].Value);
        totalBytes = ToBytes(totalValue, match.Groups[4].Value);
        if (totalBytes <= 0)
        {
            return false;
        }
        downloadedBytes = Math.Clamp(downloadedBytes, 0, totalBytes);
        return true;
    }

    private static long ToBytes(double value, string unit)
    {
        var normalized = unit.Trim().ToUpperInvariant();
        var multiplier = normalized switch
        {
            "TB" => 1_099_511_627_776d,
            "GB" => 1_073_741_824d,
            "MB" => 1_048_576d,
            "KB" => 1_024d,
            _ => 1d
        };
        return (long)Math.Max(0, Math.Round(value * multiplier));
    }

    private static Uri? ParseEndpoint(string? raw)
    {
        var candidate = string.IsNullOrWhiteSpace(raw)
            ? "http://127.0.0.1:8080/v1/chat/completions"
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
