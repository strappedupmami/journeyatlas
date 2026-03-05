using AtlasMasaWindows.Models;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using System.Text.Json;

namespace AtlasMasaWindows.Services;

public enum AuthBrowserAction
{
    AppleSignIn,
    GoogleSignIn,
    PasskeySignIn,
    PasskeySignUp
}

public sealed class AuthBrowserResult
{
    public bool IsAuthenticated { get; init; }
    public bool WasCancelled { get; init; }
    public string StatusMessage { get; init; } = string.Empty;
    public IReadOnlyList<AuthCookieRecord> Cookies { get; init; } = [];
}

public sealed class AuthBrowserFlowService
{
    private const int MaxProbeAttempts = 320;
    private const int MaxAutoKickoffAttempts = 18;
    private const int MaxCookieExportAttempts = 8;
    private const int PortalStatusPollIntervalTicks = 3;
    private static readonly TimeSpan ProbeInterval = TimeSpan.FromMilliseconds(900);
    private static readonly TimeSpan CookieExportRetryDelay = TimeSpan.FromMilliseconds(220);

    public async Task<AuthBrowserResult> RunAsync(
        Uri authPortalUri,
        Uri apiBaseUri,
        AuthBrowserAction action,
        CancellationToken cancellationToken = default)
    {
        var dispatcher = DispatcherQueue.GetForCurrentThread()
            ?? throw new InvalidOperationException("Auth flow must run on the UI thread.");

        var completion = new TaskCompletionSource<AuthBrowserResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        var window = new Window();
        var webView = new WebView2();
        var infoText = new TextBlock
        {
            Text = action switch
            {
                AuthBrowserAction.PasskeySignIn => "Click the Passwordless (more secure) Sign in button in this window, then approve the Windows passkey prompt.",
                AuthBrowserAction.PasskeySignUp => "Click the Passwordless (more secure) Sign up button in this window, then approve the Windows passkey prompt.",
                _ => "Complete secure sign-in in this window. The app will continue automatically."
            },
            Margin = new Thickness(14, 12, 14, 8),
            TextWrapping = TextWrapping.Wrap
        };

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.Children.Add(infoText);
        Grid.SetRow(webView, 1);
        root.Children.Add(webView);

        window.Title = "Atlas Secure Account Access";
        window.Content = root;

        var probeAttempts = 0;
        var finalized = false;
        var autoKickoffCompleted = false;
        var autoKickoffAttempts = 0;
        var probeInFlight = false;
        var latestPortalStatus = string.Empty;
        var latestNavigationError = string.Empty;
        var isPasskeyAction = action is AuthBrowserAction.PasskeySignIn or AuthBrowserAction.PasskeySignUp;
        var probeTimer = dispatcher.CreateTimer();
        probeTimer.Interval = ProbeInterval;

        void Complete(AuthBrowserResult result)
        {
            if (finalized)
            {
                return;
            }

            finalized = true;
            probeTimer.Stop();
            completion.TrySetResult(result);
            try
            {
                window.Close();
            }
            catch
            {
                // Best effort. Window may already be closed.
            }
        }

        async Task TryAutoKickoffAsync()
        {
            if (isPasskeyAction || autoKickoffCompleted || autoKickoffAttempts >= MaxAutoKickoffAttempts || webView.CoreWebView2 is null)
            {
                return;
            }

            autoKickoffAttempts += 1;
            var providerToken = action switch
            {
                AuthBrowserAction.AppleSignIn => "apple",
                AuthBrowserAction.GoogleSignIn => "google",
                _ => string.Empty
            };

            if (string.IsNullOrWhiteSpace(providerToken))
            {
                return;
            }

            var script = $$"""
                (() => {
                  const provider = '{{EscapeJsString(providerToken)}}';
                  const id = provider === 'apple' ? 'apple-btn' : 'google-btn';
                  const direct = document.getElementById(id);
                  if (direct && !direct.disabled) {
                    direct.click();
                    return JSON.stringify({ result: "clicked", source: "id" });
                  }

                  const candidates = Array.from(document.querySelectorAll('button,[role="button"],a'));
                  for (const candidate of candidates) {
                    const text = (candidate.innerText || candidate.textContent || "").toLowerCase();
                    if (!text.includes(provider)) {
                      continue;
                    }
                    if (candidate.disabled) {
                      continue;
                    }
                    candidate.click();
                    return JSON.stringify({ result: "clicked", source: "text" });
                  }

                  return JSON.stringify({ result: "missing", source: "" });
                })();
                """;

            try
            {
                var payload = ParseScriptPayload<AutoKickoffPayload>(await webView.ExecuteScriptAsync(script));
                if (string.Equals(payload?.Result, "clicked", StringComparison.OrdinalIgnoreCase))
                {
                    autoKickoffCompleted = true;
                }
            }
            catch
            {
                // Non-fatal: user can still continue manually.
            }
        }

        async Task TryFinalizeIfAuthenticatedAsync()
        {
            if (finalized || probeInFlight || webView.CoreWebView2 is null)
            {
                return;
            }

            probeInFlight = true;
            try
            {
                var probe = await ProbeAuthSessionAsync(webView, apiBaseUri);
                if (!probe.IsAuthenticated)
                {
                    return;
                }

                var cookies = await ExportApiCookiesWithRetriesAsync(
                    webView,
                    apiBaseUri,
                    MaxCookieExportAttempts,
                    CookieExportRetryDelay,
                    cancellationToken);
                if (cookies.Count == 0)
                {
                    Complete(new AuthBrowserResult
                    {
                        IsAuthenticated = false,
                        WasCancelled = false,
                        StatusMessage = ComposeStatus("Authentication completed, but no reusable API session cookies were available.", latestPortalStatus, latestNavigationError),
                        Cookies = []
                    });
                    return;
                }

                Complete(new AuthBrowserResult
                {
                    IsAuthenticated = true,
                    WasCancelled = false,
                    StatusMessage = string.IsNullOrWhiteSpace(probe.Provider)
                        ? "Authentication verified."
                        : $"Authentication verified ({probe.Provider}).",
                    Cookies = cookies
                });
            }
            finally
            {
                probeInFlight = false;
            }
        }

        probeTimer.Tick += async (_, _) =>
        {
            try
            {
                if (finalized)
                {
                    return;
                }

                probeAttempts += 1;
                if (!isPasskeyAction && !autoKickoffCompleted)
                {
                    await TryAutoKickoffAsync();
                }

                if (probeAttempts % PortalStatusPollIntervalTicks == 0)
                {
                    var portalStatus = await TryReadPortalStatusAsync(webView);
                    if (!string.IsNullOrWhiteSpace(portalStatus))
                    {
                        latestPortalStatus = portalStatus;
                    }
                }

                if (probeAttempts > MaxProbeAttempts)
                {
                    Complete(new AuthBrowserResult
                    {
                        IsAuthenticated = false,
                        WasCancelled = false,
                        StatusMessage = BuildTimeoutMessage(isPasskeyAction, latestPortalStatus, latestNavigationError)
                    });
                    return;
                }

                await TryFinalizeIfAuthenticatedAsync();
            }
            catch (Exception ex)
            {
                Complete(new AuthBrowserResult
                {
                    IsAuthenticated = false,
                    WasCancelled = false,
                    StatusMessage = $"Authentication runtime error: {ex.Message}"
                });
            }
        };

        webView.NavigationCompleted += async (_, args) =>
        {
            if (finalized)
            {
                return;
            }

            if (!args.IsSuccess)
            {
                latestNavigationError = $"Auth page navigation failed ({args.WebErrorStatus}).";
                return;
            }

            latestNavigationError = string.Empty;
            var portalStatus = await TryReadPortalStatusAsync(webView);
            if (!string.IsNullOrWhiteSpace(portalStatus))
            {
                latestPortalStatus = portalStatus;
            }

            await TryAutoKickoffAsync();
            await TryFinalizeIfAuthenticatedAsync();
        };

        window.Closed += (_, _) =>
        {
            if (finalized)
            {
                return;
            }

            finalized = true;
            probeTimer.Stop();
            completion.TrySetResult(new AuthBrowserResult
            {
                IsAuthenticated = false,
                WasCancelled = true,
                StatusMessage = "Authentication window was closed before completion."
            });
        };

        using var cancellationRegistration = cancellationToken.Register(() =>
        {
            var cancelledResult = new AuthBrowserResult
            {
                IsAuthenticated = false,
                WasCancelled = true,
                StatusMessage = "Authentication request was cancelled."
            };

            if (!dispatcher.TryEnqueue(() => Complete(cancelledResult)))
            {
                completion.TrySetResult(cancelledResult);
            }
        });

        window.Activate();

        try
        {
            var environment = await BuildAuthWebViewEnvironmentAsync();
            if (environment is null)
            {
                await webView.EnsureCoreWebView2Async();
            }
            else
            {
                await webView.EnsureCoreWebView2Async(environment);
            }
        }
        catch (Exception ex)
        {
            Complete(new AuthBrowserResult
            {
                IsAuthenticated = false,
                WasCancelled = false,
                StatusMessage = $"WebView2 initialization failed: {ex.Message}"
            });
            return await completion.Task;
        }

        webView.Source = authPortalUri;
        probeTimer.Start();

        return await completion.Task;
    }

    private static async Task<CoreWebView2Environment?> BuildAuthWebViewEnvironmentAsync()
    {
        try
        {
            var userDataPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Atlas",
                "Windows",
                "WebView2",
                "AuthFlow");
            Directory.CreateDirectory(userDataPath);
            return await CoreWebView2Environment.CreateAsync(userDataFolder: userDataPath);
        }
        catch
        {
            return null;
        }
    }

    private static async Task<AuthProbePayload> ProbeAuthSessionAsync(WebView2 webView, Uri apiBaseUri)
    {
        var apiBase = EscapeJsString(apiBaseUri.ToString().TrimEnd('/'));
        var script = $$"""
            (async () => {
              try {
                const response = await fetch('{{apiBase}}/v1/auth/me', {
                  method: 'GET',
                  credentials: 'include',
                  cache: 'no-store'
                });
                if (!response.ok) {
                  return JSON.stringify({ ok: false, status: response.status });
                }
                const payload = await response.json();
                return JSON.stringify({
                  ok: !!(payload && payload.user),
                  status: response.status,
                  provider: payload?.user?.provider || ""
                });
              } catch (error) {
                return JSON.stringify({
                  ok: false,
                  status: 0,
                  error: error && error.message ? error.message : "unknown"
                });
              }
            })();
            """;

        try
        {
            var rawResult = await webView.ExecuteScriptAsync(script);
            return ParseScriptPayload<AuthProbePayload>(rawResult) ?? new AuthProbePayload();
        }
        catch
        {
            return new AuthProbePayload();
        }
    }

    private static async Task<string> TryReadPortalStatusAsync(WebView2 webView)
    {
        if (webView.CoreWebView2 is null)
        {
            return string.Empty;
        }

        var script = """
            (() => {
              try {
                const statusEl = document.getElementById('auth-status');
                const message = statusEl ? (statusEl.textContent || '').trim() : '';
                const computed = statusEl ? window.getComputedStyle(statusEl) : null;
                const isVisible = !!(statusEl && computed && computed.display !== 'none' && computed.visibility !== 'hidden' && message);
                const params = new URL(window.location.href).searchParams;
                const authResult = params.get('auth');
                const authReason = params.get('reason') || '';
                if (authResult === 'error') {
                  const reasonText = authReason ? (': ' + authReason) : '';
                  return JSON.stringify({ message: 'Sign-in failed' + reasonText, source: 'query' });
                }
                if (isVisible) {
                  return JSON.stringify({ message: message, source: 'status' });
                }
                return JSON.stringify({ message: '', source: '' });
              } catch (_error) {
                return JSON.stringify({ message: '', source: '' });
              }
            })();
            """;

        try
        {
            var payload = ParseScriptPayload<PortalStatusPayload>(await webView.ExecuteScriptAsync(script));
            return payload?.Message?.Trim() ?? string.Empty;
        }
        catch
        {
            return string.Empty;
        }
    }

    private static async Task<IReadOnlyList<AuthCookieRecord>> ExportApiCookiesWithRetriesAsync(
        WebView2 webView,
        Uri apiBaseUri,
        int maxAttempts,
        TimeSpan retryDelay,
        CancellationToken cancellationToken)
    {
        for (var attempt = 1; attempt <= Math.Max(1, maxAttempts); attempt += 1)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var cookies = await ExportApiCookiesAsync(webView, apiBaseUri);
            if (cookies.Count > 0)
            {
                return cookies;
            }

            if (attempt < maxAttempts)
            {
                await Task.Delay(retryDelay, cancellationToken);
            }
        }

        return [];
    }

    private static string BuildTimeoutMessage(bool isPasskeyAction, string latestPortalStatus, string latestNavigationError)
    {
        var baseMessage = isPasskeyAction
            ? "Authentication timed out. Click Passwordless in the auth window and approve the Windows passkey prompt."
            : "Authentication timed out. Please try again.";
        return ComposeStatus(baseMessage, latestPortalStatus, latestNavigationError);
    }

    private static string ComposeStatus(string primaryMessage, string latestPortalStatus, string latestNavigationError)
    {
        if (!string.IsNullOrWhiteSpace(latestPortalStatus))
        {
            return $"{primaryMessage} Last portal status: {latestPortalStatus.Trim()}";
        }
        if (!string.IsNullOrWhiteSpace(latestNavigationError))
        {
            return $"{primaryMessage} {latestNavigationError.Trim()}";
        }
        return primaryMessage;
    }

    private static async Task<IReadOnlyList<AuthCookieRecord>> ExportApiCookiesAsync(WebView2 webView, Uri apiBaseUri)
    {
        if (webView.CoreWebView2 is null)
        {
            return [];
        }

        try
        {
            var authority = apiBaseUri.GetLeftPart(UriPartial.Authority);
            var cookies = await webView.CoreWebView2.CookieManager.GetCookiesAsync(authority);
            var nowUtc = DateTimeOffset.UtcNow;
            var mapped = new List<AuthCookieRecord>();

            foreach (var cookie in cookies)
            {
                if (string.IsNullOrWhiteSpace(cookie.Name) || string.IsNullOrWhiteSpace(cookie.Domain))
                {
                    continue;
                }

                var expiresAtUtc = cookie.IsSession
                    ? null
                    : TryReadCookieExpiryUtc(cookie);
                if (expiresAtUtc is not null && expiresAtUtc <= nowUtc)
                {
                    continue;
                }

                mapped.Add(new AuthCookieRecord
                {
                    Name = cookie.Name,
                    Value = cookie.Value,
                    Domain = cookie.Domain,
                    Path = string.IsNullOrWhiteSpace(cookie.Path) ? "/" : cookie.Path,
                    ExpiresAtUtc = expiresAtUtc,
                    Secure = cookie.IsSecure,
                    HttpOnly = cookie.IsHttpOnly,
                    SameSite = cookie.SameSite.ToString()
                });
            }

            return mapped;
        }
        catch
        {
            return [];
        }
    }

    private static DateTimeOffset? TryReadCookieExpiryUtc(CoreWebView2Cookie cookie)
    {
        try
        {
            var expiresProp = cookie.GetType().GetProperty("Expires");
            var raw = expiresProp?.GetValue(cookie);
            if (raw is DateTimeOffset dto)
            {
                return dto.ToUniversalTime();
            }
            if (raw is DateTime dt)
            {
                return new DateTimeOffset(dt.ToUniversalTime());
            }
        }
        catch
        {
            // Ignore cookie expiry parsing errors.
        }

        return null;
    }

    private static T? ParseScriptPayload<T>(string scriptResult)
    {
        if (string.IsNullOrWhiteSpace(scriptResult) || string.Equals(scriptResult, "null", StringComparison.OrdinalIgnoreCase))
        {
            return default;
        }

        try
        {
            using var wrapper = JsonDocument.Parse(scriptResult);
            if (wrapper.RootElement.ValueKind == JsonValueKind.String)
            {
                var inner = wrapper.RootElement.GetString();
                if (string.IsNullOrWhiteSpace(inner))
                {
                    return default;
                }
                return JsonSerializer.Deserialize<T>(inner);
            }

            return JsonSerializer.Deserialize<T>(scriptResult);
        }
        catch
        {
            return default;
        }
    }

    private static string EscapeJsString(string value)
    {
        return value
            .Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("'", "\\'", StringComparison.Ordinal);
    }

    private sealed class AuthProbePayload
    {
        public bool IsAuthenticated => Ok;
        public bool Ok { get; set; }
        public int Status { get; set; }
        public string? Error { get; set; }
        public string? Provider { get; set; }
    }

    private sealed class AutoKickoffPayload
    {
        public string? Result { get; set; }
        public string? Source { get; set; }
    }

    private sealed class PortalStatusPayload
    {
        public string? Message { get; set; }
        public string? Source { get; set; }
    }
}
