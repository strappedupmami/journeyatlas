using AtlasMasaWindows.Models;
using System.Text;

namespace AtlasMasaWindows.Services;

public sealed class LocalSyncBlueprintService
{
    private static readonly string[] SyncSignals =
    [
        "sync", "synchronization", "usb c", "usb-c", "peer to peer", "peer-to-peer", "p2p",
        "same network", "local network", "lan", "wifi", "wi-fi", "offline first", "offline-first",
        "device discovery", "bonjour", "mdns", "mtls", "mutual tls", "zero trust", "end to end encrypted"
    ];

    public bool LooksLikeSyncPrompt(string prompt)
    {
        var lower = (prompt ?? string.Empty).ToLowerInvariant();
        if (lower.Length < 12)
        {
            return false;
        }
        return SyncSignals.Any(lower.Contains);
    }

    public LocalReasoningOutput? TryBuildPlan(string prompt)
    {
        var normalized = (prompt ?? string.Empty).Trim();
        if (!LooksLikeSyncPrompt(normalized))
        {
            return null;
        }

        var lower = normalized.ToLowerInvariant();
        var wantsUsb = ContainsAny(lower, "usb c", "usb-c", "cable", "wired");
        var wantsLan = ContainsAny(lower, "wifi", "wi-fi", "same network", "local network", "lan", "p2p", "peer");
        var wantsZeroTrust = ContainsAny(lower, "mtls", "mutual tls", "zero trust", "certificate", "cert");

        var phases = new List<string>
        {
            "Phase 1 (Discovery): detect nearby nodes over mDNS on LAN and over direct USB-C handshake for wired mode.",
            "Phase 2 (Trust bootstrap): pair devices with one-time code + device fingerprint, then issue local certificates per device.",
            "Phase 3 (Replication): sync encrypted snapshots + append-only change log, verify signatures, and apply conflict policy."
        };

        if (!wantsLan)
        {
            phases[0] = "Phase 1 (Discovery): prioritize USB-C direct handshake, then keep LAN discovery disabled by default.";
        }

        if (!wantsUsb)
        {
            phases[0] = "Phase 1 (Discovery): prioritize mDNS + local subnet broadcast and keep wired transport optional.";
        }

        var conflictPolicy = "Conflict policy: last-write wins for low-risk preferences, CRDT/merge review for notes and queue history.";
        var trustLine = wantsZeroTrust
            ? "Transport security: enforce mTLS with per-device certificates and certificate pinning on first trusted pair."
            : "Transport security: use authenticated channels now and schedule mTLS + pinning before production release.";
        var resilienceLine = "Resilience: keep local data authoritative, queue unsent deltas offline, and replay on reconnect.";

        var summaryBuilder = new StringBuilder();
        summaryBuilder.AppendLine("Local-first sync blueprint ready.");
        summaryBuilder.AppendLine();
        summaryBuilder.AppendLine(string.Join(Environment.NewLine, phases));
        summaryBuilder.AppendLine(trustLine);
        summaryBuilder.AppendLine(conflictPolicy);
        summaryBuilder.AppendLine(resilienceLine);

        var nextAction = wantsZeroTrust
            ? "Implement device pairing first: generate per-device keypair, store fingerprint locally, then complete first mTLS handshake over USB-C."
            : "Implement discovery first: mDNS + USB-C handshake, then add certificate-based mTLS before enabling automatic background sync.";

        return new LocalReasoningOutput
        {
            Model = "atlas-local-sync-v1",
            Summary = summaryBuilder.ToString().Trim(),
            NextAction = nextAction,
            Confidence = wantsZeroTrust ? 0.85 : 0.79,
            GeneratedAt = DateTimeOffset.UtcNow
        };
    }

    private static bool ContainsAny(string text, params string[] terms)
    {
        return terms.Any(term => text.Contains(term, StringComparison.OrdinalIgnoreCase));
    }
}
