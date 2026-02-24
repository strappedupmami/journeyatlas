using AtlasMasaWindows.Models;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AtlasMasaWindows.Services;

public sealed class OnDeviceLlmClient
{
    private readonly bool _enabled;
    private readonly Uri? _endpoint;
    private readonly string _model;
    private readonly HttpClient _httpClient;
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public bool Enabled => _enabled && _endpoint is not null;

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
            return $"Local LLM bridge enabled: {_endpoint.Host}{_endpoint.AbsolutePath} · model {_model} · deterministic fallback active.";
        }
    }

    public OnDeviceLlmClient()
    {
        _enabled = ParseBool(Environment.GetEnvironmentVariable("ATLAS_LOCAL_LLM_ENABLED"), defaultValue: true);
        _model = SanitizeModel(Environment.GetEnvironmentVariable("ATLAS_LOCAL_LLM_MODEL"));
        _endpoint = ParseEndpoint(Environment.GetEnvironmentVariable("ATLAS_LOCAL_LLM_ENDPOINT"));
        _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(30)
        };
        _httpClient.DefaultRequestHeaders.Accept.Clear();
        _httpClient.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        _httpClient.DefaultRequestHeaders.CacheControl = new CacheControlHeaderValue { NoStore = true };
    }

    public async Task<LocalReasoningOutput?> TryReasonAsync(
        string prompt,
        IReadOnlyList<NoteRecord> notes,
        AtlasSessionState session,
        CancellationToken cancellationToken = default)
    {
        if (!Enabled || string.IsNullOrWhiteSpace(prompt))
        {
            return null;
        }

        var notesSnapshot = string.Join(
            "\n",
            notes.Take(16).Select(n => $"- {n.Title}: {TrimForDisplay(n.Content, 180)}"));
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

            Notes:
            {notesSnapshot}
            """;

        var requestPayload = new ChatRequest
        {
            Model = _model,
            Messages =
            [
                new ChatMessage { Role = "system", Content = "Respond with concise operational output." },
                new ChatMessage { Role = "user", Content = instruction }
            ],
            Temperature = 0.35,
            MaxTokens = 420,
            Stream = false
        };

        var raw = JsonSerializer.Serialize(requestPayload, _jsonOptions);
        using var request = new HttpRequestMessage(HttpMethod.Post, _endpoint)
        {
            Content = new StringContent(raw, Encoding.UTF8, "application/json")
        };

        try
        {
            using var response = await _httpClient.SendAsync(request, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return null;
            }

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            var envelope = JsonSerializer.Deserialize<ChatResponse>(body, _jsonOptions);
            var content =
                envelope?.Choices?.FirstOrDefault()?.Message?.Content?.Trim()
                ?? envelope?.Choices?.FirstOrDefault()?.Text?.Trim();
            if (string.IsNullOrWhiteSpace(content))
            {
                return null;
            }

            var parsed = ParseQueueJson(content);
            if (parsed is null)
            {
                return null;
            }

            return new LocalReasoningOutput
            {
                Model = $"atlas-local-llm/{TrimForDisplay(_model, 64)}",
                Summary = TrimForDisplay(parsed.Summary, 420),
                NextAction = TrimForDisplay(parsed.NextAction, 220),
                Confidence = Math.Clamp(parsed.Confidence, 0.0, 1.0),
                GeneratedAt = DateTimeOffset.UtcNow
            };
        }
        catch
        {
            return null;
        }
    }

    private sealed class ParsedQueue
    {
        public string Summary { get; init; } = string.Empty;
        public string NextAction { get; init; } = string.Empty;
        public double Confidence { get; init; } = 0.66;
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
            return "atlas-local-3b";
        }
        return value.Trim();
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
