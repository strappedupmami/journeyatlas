using AtlasMasaWindows.Models;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AtlasMasaWindows.Services;

public sealed class AtlasApiClient
{
    private readonly Uri _baseUri;
    private readonly CookieContainer _cookieContainer;
    private readonly HttpClient _httpClient;
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public string BaseUrl => _baseUri.ToString().TrimEnd('/');
    public string Host => _baseUri.Host;

    public AtlasApiClient(string baseUrl, IEnumerable<AuthCookieRecord>? persistedAuthCookies = null)
    {
        var sanitized = AtlasBackendConfig.SanitizeApiBase(baseUrl);
        _baseUri = new Uri(sanitized, UriKind.Absolute);
        if (!AtlasBackendConfig.IsAllowedApiBase(_baseUri))
        {
            throw new InvalidOperationException("Blocked insecure or untrusted backend API base.");
        }

        _cookieContainer = new CookieContainer();
        var handler = new HttpClientHandler
        {
            AllowAutoRedirect = false,
            UseCookies = true,
            CookieContainer = _cookieContainer
        };

        _httpClient = new HttpClient(handler)
        {
            Timeout = TimeSpan.FromSeconds(20)
        };
        _httpClient.DefaultRequestHeaders.Accept.Clear();
        _httpClient.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        _httpClient.DefaultRequestHeaders.CacheControl = new CacheControlHeaderValue { NoStore = true };

        if (persistedAuthCookies is not null)
        {
            ImportAuthCookies(persistedAuthCookies);
        }
    }

    public sealed class AuthSessionUser
    {
        public string Provider { get; init; } = "passkey";
        public string? Name { get; init; }
        public string? Email { get; init; }
        public bool PrepaidCreditsActive { get; init; }
    }

    public enum AuthProbeState
    {
        Authenticated,
        Unauthenticated,
        Unreachable
    }

    public sealed class AuthSessionProbeResult
    {
        public AuthProbeState State { get; init; }
        public AuthSessionUser? User { get; init; }
        public int StatusCode { get; init; }
        public string? Error { get; init; }
    }

    public async Task<string> HealthStatusLineAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            using var request = BuildRequest(HttpMethod.Get, "/health");
            using var response = await _httpClient.SendAsync(request, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return $"API health unavailable on {Host}. Local-first mode remains active.";
            }

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            var payload = JsonSerializer.Deserialize<HealthWire>(body, _jsonOptions);
            var caps = payload?.Capabilities ?? new CapabilitiesWire();
            return $"API health ok ({Host}): google={caps.GoogleOAuth} apple={caps.AppleOAuth} passkey={caps.Passkey} billing={caps.Billing}";
        }
        catch
        {
            return $"API health unavailable on {Host}. Local-first mode remains active.";
        }
    }

    public async Task<AuthSessionUser?> AuthMeAsync(CancellationToken cancellationToken = default)
    {
        var probe = await ProbeAuthSessionAsync(cancellationToken);
        return probe.State == AuthProbeState.Authenticated ? probe.User : null;
    }

    public async Task<AuthSessionProbeResult> ProbeAuthSessionAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            using var request = BuildRequest(HttpMethod.Get, "/v1/auth/me");
            using var response = await _httpClient.SendAsync(request, cancellationToken);
            if (response.StatusCode == HttpStatusCode.Unauthorized || response.StatusCode == HttpStatusCode.Forbidden)
            {
                return new AuthSessionProbeResult
                {
                    State = AuthProbeState.Unauthenticated,
                    StatusCode = (int)response.StatusCode
                };
            }

            if (!response.IsSuccessStatusCode)
            {
                return new AuthSessionProbeResult
                {
                    State = AuthProbeState.Unreachable,
                    StatusCode = (int)response.StatusCode,
                    Error = $"Auth probe failed with status {(int)response.StatusCode}."
                };
            }

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            var payload = JsonSerializer.Deserialize<AuthMeWire>(body, _jsonOptions);
            if (payload?.User is null)
            {
                return new AuthSessionProbeResult
                {
                    State = AuthProbeState.Unauthenticated,
                    StatusCode = (int)response.StatusCode
                };
            }

            var user = new AuthSessionUser
            {
                Provider = string.IsNullOrWhiteSpace(payload.User.Provider) ? "passkey" : payload.User.Provider,
                Name = payload.User.Name,
                Email = payload.User.Email,
                PrepaidCreditsActive = payload.Subscription?.UsageBillingActive
                    ?? payload.Subscription?.CloudComputeEnabled
                    ?? false
            };

            return new AuthSessionProbeResult
            {
                State = AuthProbeState.Authenticated,
                User = user,
                StatusCode = (int)response.StatusCode
            };
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            return new AuthSessionProbeResult
            {
                State = AuthProbeState.Unreachable,
                StatusCode = 0,
                Error = ex.Message
            };
        }
    }

    public async Task<string?> ChatReplyAsync(
        string prompt,
        string? locale,
        string? preferredFormat = null,
        string? responseDepth = null,
        string? responseTone = null,
        bool? includeProactive = null,
        string? codeAgentRoute = null,
        CancellationToken cancellationToken = default)
    {
        var trimmed = (prompt ?? string.Empty).Trim();
        if (trimmed.Length == 0)
        {
            return null;
        }

        try
        {
            var payload = new ChatRequestWire
            {
                Text = trimmed,
                Locale = string.IsNullOrWhiteSpace(locale) ? null : locale.Trim(),
                PreferredFormat = preferredFormat,
                ResponseDepth = responseDepth,
                ResponseTone = responseTone,
                IncludeProactive = includeProactive,
                CodeAgentRoute = codeAgentRoute
            };
            var jsonBody = JsonSerializer.Serialize(payload, _jsonOptions);
            using var request = BuildRequest(HttpMethod.Post, "/v1/chat", jsonBody);
            using var response = await _httpClient.SendAsync(request, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return null;
            }

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            var parsed = JsonSerializer.Deserialize<ChatResponseWire>(body, _jsonOptions);
            var reply = parsed?.ReplyText?.Trim();
            return string.IsNullOrWhiteSpace(reply) ? null : reply;
        }
        catch
        {
            return null;
        }
    }

    public async Task LogoutAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            using var request = BuildRequest(HttpMethod.Post, "/v1/auth/logout", "{}");
            _ = await _httpClient.SendAsync(request, cancellationToken);
        }
        catch
        {
            // best-effort logout only
        }
    }

    public IReadOnlyList<AuthCookieRecord> ExportAuthCookies()
    {
        var nowUtc = DateTimeOffset.UtcNow;
        var exported = new List<AuthCookieRecord>();

        foreach (Cookie cookie in _cookieContainer.GetCookies(_baseUri))
        {
            if (string.IsNullOrWhiteSpace(cookie.Name))
            {
                continue;
            }

            DateTimeOffset? expiresAtUtc = null;
            if (cookie.Expires != DateTime.MinValue)
            {
                var parsed = new DateTimeOffset(cookie.Expires.ToUniversalTime());
                if (parsed <= nowUtc)
                {
                    continue;
                }
                expiresAtUtc = parsed;
            }

            exported.Add(new AuthCookieRecord
            {
                Name = cookie.Name,
                Value = cookie.Value,
                Domain = string.IsNullOrWhiteSpace(cookie.Domain) ? _baseUri.Host : cookie.Domain,
                Path = string.IsNullOrWhiteSpace(cookie.Path) ? "/" : cookie.Path,
                ExpiresAtUtc = expiresAtUtc,
                Secure = cookie.Secure,
                HttpOnly = cookie.HttpOnly,
                SameSite = cookie.SameSite.ToString()
            });
        }

        return exported;
    }

    public void ImportAuthCookies(IEnumerable<AuthCookieRecord> cookies)
    {
        var nowUtc = DateTimeOffset.UtcNow;
        foreach (var persisted in cookies)
        {
            if (string.IsNullOrWhiteSpace(persisted.Name) || string.IsNullOrWhiteSpace(persisted.Domain))
            {
                continue;
            }
            if (persisted.ExpiresAtUtc is not null && persisted.ExpiresAtUtc <= nowUtc)
            {
                continue;
            }
            if (!CookieDomainMatchesBaseHost(persisted.Domain))
            {
                continue;
            }

            try
            {
                var normalizedDomain = NormalizeCookieDomain(persisted.Domain);
                var cookieDomain = FormatCookieDomainForContainer(normalizedDomain);
                var path = string.IsNullOrWhiteSpace(persisted.Path) ? "/" : persisted.Path;
                var cookie = new Cookie(persisted.Name, persisted.Value, path, cookieDomain)
                {
                    HttpOnly = persisted.HttpOnly,
                    Secure = persisted.Secure
                };

                if (persisted.ExpiresAtUtc is not null)
                {
                    cookie.Expires = persisted.ExpiresAtUtc.Value.UtcDateTime;
                }

                if (Enum.TryParse<SameSiteMode>(persisted.SameSite, ignoreCase: true, out var sameSite))
                {
                    cookie.SameSite = sameSite;
                }

                _cookieContainer.Add(BuildCookieUri(normalizedDomain, persisted.Secure), cookie);
            }
            catch
            {
                // Ignore malformed cookie payloads and continue importing the rest.
            }
        }
    }

    private HttpRequestMessage BuildRequest(HttpMethod method, string path, string? jsonBody = null)
    {
        if (path.Contains("://", StringComparison.Ordinal) || path.StartsWith("//", StringComparison.Ordinal))
        {
            throw new InvalidOperationException("Blocked unsafe API path.");
        }
        if (!path.StartsWith("/", StringComparison.Ordinal))
        {
            throw new InvalidOperationException("API path must start with '/'.");
        }

        var target = new Uri(_baseUri, path);
        if (!string.Equals(target.Host, _baseUri.Host, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Blocked host mismatch in API path.");
        }
        if (!AtlasBackendConfig.IsAllowedApiBase(new Uri(target.GetLeftPart(UriPartial.Authority))))
        {
            throw new InvalidOperationException("Blocked insecure API transport.");
        }

        var request = new HttpRequestMessage(method, target);
        request.Headers.TryAddWithoutValidation("X-Client", "AtlasMasaWindows/1.0");
        request.Headers.TryAddWithoutValidation("Origin", AtlasBackendConfig.OriginHeaderValue(_baseUri));
        request.Headers.Accept.Clear();
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Headers.CacheControl = new CacheControlHeaderValue { NoStore = true };

        if (jsonBody is not null)
        {
            request.Content = new StringContent(jsonBody, Encoding.UTF8, "application/json");
        }
        return request;
    }

    private bool CookieDomainMatchesBaseHost(string rawDomain)
    {
        var domain = NormalizeCookieDomain(rawDomain);
        var baseHost = _baseUri.Host.ToLowerInvariant();
        return domain == baseHost || baseHost.EndsWith($".{domain}", StringComparison.Ordinal);
    }

    private static string NormalizeCookieDomain(string rawDomain)
    {
        return rawDomain.Trim().TrimStart('.').ToLowerInvariant();
    }

    private string FormatCookieDomainForContainer(string normalizedDomain)
    {
        var baseHost = _baseUri.Host.ToLowerInvariant();
        if (string.Equals(normalizedDomain, baseHost, StringComparison.Ordinal))
        {
            return baseHost;
        }
        return $".{normalizedDomain}";
    }

    private Uri BuildCookieUri(string normalizedDomain, bool secureCookie)
    {
        var scheme = secureCookie ? Uri.UriSchemeHttps : _baseUri.Scheme;
        return new Uri($"{scheme}://{normalizedDomain}/", UriKind.Absolute);
    }

    private sealed class HealthWire
    {
        [JsonPropertyName("capabilities")]
        public CapabilitiesWire? Capabilities { get; set; }
    }

    private sealed class CapabilitiesWire
    {
        [JsonPropertyName("google_oauth")]
        public bool GoogleOAuth { get; set; }

        [JsonPropertyName("apple_oauth")]
        public bool AppleOAuth { get; set; }

        [JsonPropertyName("passkey")]
        public bool Passkey { get; set; } = true;

        [JsonPropertyName("billing")]
        public bool Billing { get; set; }
    }

    private sealed class AuthMeWire
    {
        [JsonPropertyName("user")]
        public AuthUserWire? User { get; set; }

        [JsonPropertyName("subscription")]
        public AuthSubscriptionWire? Subscription { get; set; }
    }

    private sealed class AuthUserWire
    {
        [JsonPropertyName("provider")]
        public string Provider { get; set; } = "passkey";

        [JsonPropertyName("name")]
        public string? Name { get; set; }

        [JsonPropertyName("email")]
        public string? Email { get; set; }
    }

    private sealed class AuthSubscriptionWire
    {
        [JsonPropertyName("cloud_compute_enabled")]
        public bool? CloudComputeEnabled { get; set; }

        [JsonPropertyName("usage_billing_active")]
        public bool? UsageBillingActive { get; set; }
    }

    private sealed class ChatRequestWire
    {
        [JsonPropertyName("session_id")]
        public string? SessionId { get; set; }

        [JsonPropertyName("text")]
        public string Text { get; set; } = string.Empty;

        [JsonPropertyName("locale")]
        public string? Locale { get; set; }

        [JsonPropertyName("user_id")]
        public string? UserId { get; set; }

        [JsonPropertyName("preferred_format")]
        public string? PreferredFormat { get; set; }

        [JsonPropertyName("response_depth")]
        public string? ResponseDepth { get; set; }

        [JsonPropertyName("response_tone")]
        public string? ResponseTone { get; set; }

        [JsonPropertyName("include_proactive")]
        public bool? IncludeProactive { get; set; }

        [JsonPropertyName("code_agent_route")]
        public string? CodeAgentRoute { get; set; }
    }

    private sealed class ChatResponseWire
    {
        [JsonPropertyName("reply_text")]
        public string? ReplyText { get; set; }
    }
}
