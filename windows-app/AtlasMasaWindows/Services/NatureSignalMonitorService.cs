using AtlasMasaWindows.Models;
using System.Text.Json;

namespace AtlasMasaWindows.Services;

public sealed class NatureSignalMonitorService
{
    private readonly HttpClient _httpClient = new()
    {
        Timeout = TimeSpan.FromSeconds(18)
    };

    public async Task<NatureSignalSnapshot> CaptureSnapshotAsync(
        int elevatedThreshold,
        int criticalThreshold,
        CancellationToken cancellationToken = default)
    {
        var now = DateTimeOffset.UtcNow;
        var tiles = new List<NatureSignalTile>();
        var risk = 18;
        var uncertaintyPenalty = 0;

        var iucnTokenPresent = !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("IUCN_REDLIST_TOKEN"));
        tiles.Add(new NatureSignalTile
        {
            Id = "iucn_red_list_api",
            Title = "IUCN Red List API",
            Metric = iucnTokenPresent ? "Token configured" : "Token missing",
            Trend = iucnTokenPresent ? "ready" : "data_blind_spot",
            Severity = iucnTokenPresent ? "info" : "warning",
            SourceLabel = "api.iucnredlist.org",
            SourceUrl = "https://api.iucnredlist.org/",
            UpdatedAt = now
        });
        if (!iucnTokenPresent)
        {
            risk += 12;
        }

        var gbifCurrent = await TryFetchGbifOccurrenceCountAsync(DateTime.UtcNow.Year, cancellationToken);
        var gbifPrevious = await TryFetchGbifOccurrenceCountAsync(DateTime.UtcNow.Year - 1, cancellationToken);
        if (gbifCurrent is not null && gbifPrevious is not null && gbifPrevious > 0)
        {
            var deltaPct = ((double)gbifCurrent.Value - gbifPrevious.Value) / gbifPrevious.Value * 100.0;
            tiles.Add(new NatureSignalTile
            {
                Id = "gbif_occurrence_trend",
                Title = "GBIF occurrence trend",
                Metric = $"{gbifCurrent:N0} vs {gbifPrevious:N0} ({deltaPct:+0.0;-0.0;0.0}%)",
                Trend = deltaPct < -8 ? "declining" : deltaPct > 8 ? "rising" : "stable",
                Severity = deltaPct < -15 ? "critical" : deltaPct < -8 ? "warning" : "info",
                SourceLabel = "api.gbif.org",
                SourceUrl = "https://api.gbif.org/v1/",
                UpdatedAt = now
            });

            if (deltaPct < -15)
            {
                risk += 18;
            }
            else if (deltaPct < -8)
            {
                risk += 10;
            }
        }
        else
        {
            tiles.Add(new NatureSignalTile
            {
                Id = "gbif_occurrence_trend",
                Title = "GBIF occurrence trend",
                Metric = "Unavailable",
                Trend = "unknown",
                Severity = "warning",
                SourceLabel = "api.gbif.org",
                SourceUrl = "https://api.gbif.org/v1/",
                UpdatedAt = now
            });
            uncertaintyPenalty += 4;
        }

        var eonetOpenEvents = await TryFetchEonetOpenEventCountAsync(cancellationToken);
        if (eonetOpenEvents is not null)
        {
            tiles.Add(new NatureSignalTile
            {
                Id = "nasa_eonet_open_events",
                Title = "NASA EONET open events",
                Metric = $"{eonetOpenEvents} active events",
                Trend = eonetOpenEvents >= 120 ? "rising" : eonetOpenEvents <= 50 ? "stable" : "elevated",
                Severity = eonetOpenEvents >= 150 ? "critical" : eonetOpenEvents >= 100 ? "warning" : "info",
                SourceLabel = "eonet.gsfc.nasa.gov",
                SourceUrl = "https://eonet.gsfc.nasa.gov/api/v3/events?status=open",
                UpdatedAt = now
            });

            risk += Math.Clamp(eonetOpenEvents.Value / 8, 0, 22);
        }
        else
        {
            tiles.Add(new NatureSignalTile
            {
                Id = "nasa_eonet_open_events",
                Title = "NASA EONET open events",
                Metric = "Unavailable",
                Trend = "unknown",
                Severity = "warning",
                SourceLabel = "eonet.gsfc.nasa.gov",
                SourceUrl = "https://eonet.gsfc.nasa.gov/api/v3/events?status=open",
                UpdatedAt = now
            });
            uncertaintyPenalty += 4;
        }

        var firmsKeyPresent = !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("NASA_FIRMS_API_KEY"));
        tiles.Add(new NatureSignalTile
        {
            Id = "nasa_firms_access",
            Title = "NASA FIRMS feed access",
            Metric = firmsKeyPresent ? "Map key configured" : "Map key missing",
            Trend = firmsKeyPresent ? "ready" : "blocked",
            Severity = firmsKeyPresent ? "info" : "warning",
            SourceLabel = "firms.modaps.eosdis.nasa.gov",
            SourceUrl = "https://firms.modaps.eosdis.nasa.gov/",
            UpdatedAt = now
        });
        if (!firmsKeyPresent)
        {
            risk += 8;
        }

        var climateHeartbeat = await TryFetchHeartbeatAsync("https://climate.copernicus.eu/climate-bulletins", cancellationToken);
        tiles.Add(new NatureSignalTile
        {
            Id = "copernicus_climate_heartbeat",
            Title = "Copernicus climate bulletins",
            Metric = climateHeartbeat ? "Endpoint reachable" : "Endpoint unavailable",
            Trend = climateHeartbeat ? "stable" : "degraded",
            Severity = climateHeartbeat ? "info" : "warning",
            SourceLabel = "climate.copernicus.eu",
            SourceUrl = "https://climate.copernicus.eu/climate-bulletins",
            UpdatedAt = now
        });
        if (!climateHeartbeat)
        {
            uncertaintyPenalty += 3;
        }

        risk += uncertaintyPenalty;
        risk = Math.Clamp(risk, 0, 100);

        var riskBand = risk >= criticalThreshold
            ? "critical"
            : risk >= elevatedThreshold
                ? "elevated"
                : "low";
        var alertSummary = riskBand switch
        {
            "critical" => "Nature risk is critical. Tighten climate/biodiversity watch and increase execution pace on wealth-building donation capacity.",
            "elevated" => "Nature risk is elevated. Keep mitigation monitoring active and prioritize income-generating actions for donation runway.",
            _ => "Nature risk is stable. Maintain steady monitoring and compounding execution discipline."
        };

        return new NatureSignalSnapshot
        {
            Tiles = tiles,
            RiskScore = risk,
            RiskBand = riskBand,
            AlertSummary = alertSummary,
            RefreshedAt = now
        };
    }

    private async Task<long?> TryFetchGbifOccurrenceCountAsync(int year, CancellationToken cancellationToken)
    {
        try
        {
            var url = $"https://api.gbif.org/v1/occurrence/search?year={year}&limit=0";
            using var response = await _httpClient.GetAsync(url, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return null;
            }

            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
            if (doc.RootElement.TryGetProperty("count", out var countNode) &&
                countNode.TryGetInt64(out var count))
            {
                return Math.Max(0, count);
            }
            return null;
        }
        catch
        {
            return null;
        }
    }

    private async Task<int?> TryFetchEonetOpenEventCountAsync(CancellationToken cancellationToken)
    {
        try
        {
            using var response = await _httpClient.GetAsync("https://eonet.gsfc.nasa.gov/api/v3/events?status=open&limit=300", cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return null;
            }

            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
            if (!doc.RootElement.TryGetProperty("events", out var eventsNode) || eventsNode.ValueKind != JsonValueKind.Array)
            {
                return null;
            }
            return eventsNode.GetArrayLength();
        }
        catch
        {
            return null;
        }
    }

    private async Task<bool> TryFetchHeartbeatAsync(string url, CancellationToken cancellationToken)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            using var response = await _httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }
}
