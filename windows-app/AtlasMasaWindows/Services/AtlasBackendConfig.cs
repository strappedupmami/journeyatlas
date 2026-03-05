namespace AtlasMasaWindows.Services;

public static class AtlasBackendConfig
{
    public const string DefaultApiBase = "https://api.atlasmasa.com";

    private static readonly HashSet<string> ProductionHosts = new(StringComparer.OrdinalIgnoreCase)
    {
        "api.atlasmasa.com",
        "journeyatlas-production.up.railway.app"
    };

    private static readonly HashSet<string> LocalDebugHosts = new(StringComparer.OrdinalIgnoreCase)
    {
        "localhost",
        "127.0.0.1"
    };

    public static string ResolveStartupApiBase(string? persistedValue)
    {
        var fromEnv = Environment.GetEnvironmentVariable("ATLAS_API_BASE");
        if (!string.IsNullOrWhiteSpace(fromEnv))
        {
            return SanitizeApiBase(fromEnv);
        }
        return SanitizeApiBase(persistedValue);
    }

    public static string SanitizeApiBase(string? rawValue)
    {
        var cleaned = (rawValue ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(cleaned))
        {
            return DefaultApiBase;
        }

        if (!Uri.TryCreate(cleaned, UriKind.Absolute, out var parsed))
        {
            return DefaultApiBase;
        }

        var normalized = TrimTrailingSlash(parsed.ToString());
        if (!Uri.TryCreate(normalized, UriKind.Absolute, out var normalizedUri))
        {
            return DefaultApiBase;
        }

        return IsAllowedApiBase(normalizedUri) ? normalized : DefaultApiBase;
    }

    public static bool IsAllowedApiBase(Uri uri)
    {
        if (uri.Scheme.Equals("https", StringComparison.OrdinalIgnoreCase))
        {
            if (AllowDebugHosts)
            {
                return true;
            }
            return ProductionHosts.Contains(uri.Host);
        }

        if (uri.Scheme.Equals("http", StringComparison.OrdinalIgnoreCase))
        {
            return AllowDebugHosts && LocalDebugHosts.Contains(uri.Host);
        }

        return false;
    }

    public static string OriginHeaderValue(Uri apiBaseUri)
    {
        var host = apiBaseUri.Host.ToLowerInvariant();
        if (LocalDebugHosts.Contains(host))
        {
            var scheme = apiBaseUri.Scheme.Equals("https", StringComparison.OrdinalIgnoreCase) ? "https" : "http";
            var port = apiBaseUri.IsDefaultPort ? 5500 : apiBaseUri.Port;
            return $"{scheme}://{host}:{port}";
        }
        return "https://atlasmasa.com";
    }

    private static bool AllowDebugHosts
    {
        get
        {
#if DEBUG
            return true;
#else
            return false;
#endif
        }
    }

    private static string TrimTrailingSlash(string value)
    {
        return value.Trim().TrimEnd('/');
    }
}
