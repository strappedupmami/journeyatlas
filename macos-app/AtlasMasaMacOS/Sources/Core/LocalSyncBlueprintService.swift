import Foundation

struct LocalSyncBlueprintService {
    private let syncSignals = [
        "sync", "synchronization", "usb c", "usb-c", "peer to peer", "peer-to-peer", "p2p",
        "same network", "local network", "lan", "wifi", "wi-fi", "offline first", "offline-first",
        "device discovery", "bonjour", "mdns", "mtls", "mutual tls", "zero trust", "end to end encrypted",
    ]

    func looksLikeSyncPrompt(_ prompt: String) -> Bool {
        let lower = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.count >= 12 else { return false }
        return syncSignals.contains { lower.contains($0) }
    }

    func buildPlan(prompt: String) -> LocalReasoningOutput? {
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeSyncPrompt(normalized) else { return nil }

        let lower = normalized.lowercased()
        let wantsUSB = containsAny(lower, ["usb c", "usb-c", "cable", "wired"])
        let wantsLAN = containsAny(lower, ["wifi", "wi-fi", "same network", "local network", "lan", "p2p", "peer"])
        let wantsZeroTrust = containsAny(lower, ["mtls", "mutual tls", "zero trust", "certificate", "cert"])

        var phase1 = "Phase 1 (Discovery): detect nearby nodes over mDNS on LAN and over direct USB-C handshake for wired mode."
        if !wantsLAN {
            phase1 = "Phase 1 (Discovery): prioritize USB-C direct handshake, then keep LAN discovery disabled by default."
        } else if !wantsUSB {
            phase1 = "Phase 1 (Discovery): prioritize mDNS + local subnet broadcast and keep wired transport optional."
        }

        let trustLine: String = wantsZeroTrust
            ? "Transport security: enforce mTLS with per-device certificates and certificate pinning on first trusted pair."
            : "Transport security: use authenticated channels now and schedule mTLS + pinning before production release."
        let phase2 = "Phase 2 (Trust bootstrap): pair devices with one-time code + device fingerprint, then issue local certificates per device."
        let phase3 = "Phase 3 (Replication): sync encrypted snapshots + append-only change log, verify signatures, and apply conflict policy."
        let conflictPolicy = "Conflict policy: last-write wins for low-risk preferences, CRDT/merge review for notes and queue history."
        let resilience = "Resilience: keep local data authoritative, queue unsent deltas offline, and replay on reconnect."

        let summary = [
            "Local-first sync blueprint ready.",
            "",
            phase1,
            phase2,
            phase3,
            trustLine,
            conflictPolicy,
            resilience,
        ].joined(separator: "\n")

        let nextAction: String = wantsZeroTrust
            ? "Implement device pairing first: generate per-device keypair, store fingerprint locally, then complete first mTLS handshake over USB-C."
            : "Implement discovery first: mDNS + USB-C handshake, then add certificate-based mTLS before enabling automatic background sync."

        return LocalReasoningOutput(
            model: "atlas-local-sync-v1",
            summary: summary,
            nextAction: nextAction,
            confidence: wantsZeroTrust ? 0.85 : 0.79,
            generatedAt: Date()
        )
    }

    private func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }
}
