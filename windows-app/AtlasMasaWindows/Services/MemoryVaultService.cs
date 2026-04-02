using AtlasMasaWindows.Models;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AtlasMasaWindows.Services;

public sealed class MemoryVaultService
{
    private const string FileName = "atlas_memory_vault_v1.json";
    private static readonly byte[] EnvelopeHeader = Encoding.UTF8.GetBytes("ATLASMV1");
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("atlas/windows/memory_vault/v1");
    private readonly string _directory;
    private readonly string _filePath;
    private readonly string _tmpFilePath;
    private readonly JsonSerializerOptions _jsonOptions;
    private readonly SemaphoreSlim _fileLock = new(1, 1);

    public MemoryVaultService()
    {
        _directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Atlas",
            "Windows",
            "Vault");
        _filePath = Path.Combine(_directory, FileName);
        _tmpFilePath = Path.Combine(_directory, $"{FileName}.tmp");
        _jsonOptions = new JsonSerializerOptions
        {
            WriteIndented = true,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };
    }

    public async Task<MemoryVaultSnapshot> LoadAsync(CancellationToken cancellationToken = default)
    {
        await _fileLock.WaitAsync(cancellationToken);
        try
        {
            if (!File.Exists(_filePath))
            {
                return new MemoryVaultSnapshot();
            }

            var bytes = await File.ReadAllBytesAsync(_filePath, cancellationToken);
            var plaintext = TryDecryptEnvelope(bytes) ?? bytes;
            return JsonSerializer.Deserialize<MemoryVaultSnapshot>(plaintext, _jsonOptions) ?? new MemoryVaultSnapshot();
        }
        catch
        {
            return new MemoryVaultSnapshot();
        }
        finally
        {
            _fileLock.Release();
        }
    }

    public async Task SaveAsync(MemoryVaultSnapshot snapshot, CancellationToken cancellationToken = default)
    {
        await _fileLock.WaitAsync(cancellationToken);
        try
        {
            Directory.CreateDirectory(_directory);
            snapshot.LastSavedAt = DateTimeOffset.UtcNow;
            var plaintext = JsonSerializer.SerializeToUtf8Bytes(snapshot, _jsonOptions);
            var encrypted = EncryptEnvelope(plaintext);
            await File.WriteAllBytesAsync(_tmpFilePath, encrypted, cancellationToken);
            if (File.Exists(_filePath))
            {
                File.Replace(_tmpFilePath, _filePath, null, true);
            }
            else
            {
                File.Move(_tmpFilePath, _filePath);
            }
        }
        finally
        {
            _fileLock.Release();
        }
    }

    public MemoryVaultPolicy ResolvePolicy(
        SystemPerformanceProfile performance,
        IReadOnlyList<string>? selectedModels = null)
    {
        var heavyModel = selectedModels?.Any(model =>
            model.Contains("32b", StringComparison.OrdinalIgnoreCase)
            || model.Contains("70b", StringComparison.OrdinalIgnoreCase)
            || model.Contains("14b", StringComparison.OrdinalIgnoreCase)) == true;

        var contextBudgetTokens = performance.UltraPerformanceMode
            ? 16_000
            : performance.HighPerformanceMode
                ? 10_000
                : 6_000;
        if (!heavyModel && performance.HighPerformanceMode)
        {
            contextBudgetTokens += 1_500;
        }

        var compactionThresholdTokens = (int)Math.Round(contextBudgetTokens * 0.78);
        var retrievalDepth = performance.UltraPerformanceMode ? 8 : performance.HighPerformanceMode ? 6 : 4;
        var responseBudget = performance.UltraPerformanceMode ? 1_600 : performance.HighPerformanceMode ? 1_200 : 820;

        return new MemoryVaultPolicy
        {
            HardwareTier = performance.Label,
            ContextBudgetTokens = contextBudgetTokens,
            CompactionThresholdTokens = compactionThresholdTokens,
            RetrievalDepth = retrievalDepth,
            ResponseBudgetTokens = responseBudget,
            ArchiveSearchMode = "native_encrypted_local_index",
            ModelGuidance = heavyModel ? "heavier_local_model" : "balanced_local_model"
        };
    }

    public MemoryVaultSnapshot SyncFromCurrentState(
        MemoryVaultSnapshot snapshot,
        IReadOnlyList<NoteRecord> notes,
        IReadOnlyList<MemoryRecord> memory,
        IReadOnlyList<QueueRecord> queue,
        MemoryVaultPolicy policy,
        string reason)
    {
        snapshot.SchemaVersion = 1;
        snapshot.RawRecords = snapshot.RawRecords ?? [];
        snapshot.CompactedRecords = snapshot.CompactedRecords ?? [];
        snapshot.ArtifactRecords = snapshot.ArtifactRecords ?? [];

        foreach (var note in notes.Take(48))
        {
            UpsertRawRecord(
                snapshot,
                recordId: $"note:{note.Id}",
                sourceType: "note",
                sourceLabel: "windows_note",
                tags: ["notes", "manual_capture"],
                content: $"{note.Title}: {note.Content}",
                createdAt: note.CreatedAt);
        }

        foreach (var item in memory.Take(320))
        {
            UpsertRawRecord(
                snapshot,
                recordId: $"memory:{item.Id}",
                sourceType: item.Type,
                sourceLabel: item.Source,
                tags: item.Tags,
                content: item.Value,
                createdAt: item.Recency);
        }

        foreach (var item in queue.Take(120))
        {
            var body = item.OutputSummary ?? item.Prompt;
            UpsertRawRecord(
                snapshot,
                recordId: $"queue:{item.Id}",
                sourceType: "queue",
                sourceLabel: item.CodeAgentRoute ?? "general",
                tags: ["queue", item.Status.ToString().ToLowerInvariant()],
                content: body,
                createdAt: item.CreatedAt);
        }

        TrimSnapshot(snapshot);

        var activeRaw = snapshot.RawRecords
            .Where(record => !record.DeepArchived)
            .OrderByDescending(record => record.CreatedAt)
            .ToList();
        var estimatedTokens = EstimateTokens(activeRaw.Sum(record => record.Content.Length) + snapshot.CompactedRecords.Sum(record => record.Summary.Length));
        snapshot.LastTokenPressure = estimatedTokens;
        snapshot.LastSyncReason = reason;
        snapshot.LastPolicy = policy;

        if (estimatedTokens >= policy.CompactionThresholdTokens)
        {
            snapshot = CompactOldestRecords(snapshot, policy, reason);
        }

        return snapshot;
    }

    public MemoryVaultSnapshot CompactFurther(MemoryVaultSnapshot snapshot, MemoryVaultPolicy policy)
    {
        return CompactOldestRecords(snapshot, policy, "manual_compact_further");
    }

    public MemoryVaultSnapshot DeepArchive(MemoryVaultSnapshot snapshot)
    {
        var candidates = snapshot.RawRecords
            .Where(record => !record.DeepArchived)
            .OrderBy(record => record.CreatedAt)
            .Take(24)
            .ToList();
        foreach (var candidate in candidates)
        {
            candidate.DeepArchived = true;
        }

        snapshot.LastCompactionReason = "manual_deep_archive";
        snapshot.LastCompactedAt = DateTimeOffset.UtcNow;
        snapshot.LastArchiveMode = "deep_archive";
        return snapshot;
    }

    public MemoryVaultSnapshot Scrub(MemoryVaultSnapshot snapshot)
    {
        snapshot.RawRecords.Clear();
        snapshot.CompactedRecords.Clear();
        snapshot.ArtifactRecords.Clear();
        snapshot.LastTokenPressure = 0;
        snapshot.LastCompactionReason = "user_scrub";
        snapshot.LastArchiveMode = "scrubbed";
        snapshot.LastCompactedAt = DateTimeOffset.UtcNow;
        return snapshot;
    }

    public IReadOnlyList<MemoryRecallHit> Recall(
        MemoryVaultSnapshot snapshot,
        string query,
        int limit)
    {
        var normalized = query.Trim().ToLowerInvariant();
        if (normalized.Length == 0)
        {
            return [];
        }

        var hits = snapshot.RawRecords
            .Select(record =>
            {
                var haystack = $"{record.SourceType} {record.SourceLabel} {string.Join(" ", record.Tags)} {record.Content}".ToLowerInvariant();
                var score = normalized.Split(' ', StringSplitOptions.RemoveEmptyEntries)
                    .Where(token => token.Length > 1)
                    .Sum(token => haystack.Contains(token, StringComparison.Ordinal) ? 2 : 0);
                if (haystack.Contains(normalized, StringComparison.Ordinal))
                {
                    score += 3;
                }
                return new { Record = record, Score = score };
            })
            .Where(pair => pair.Score > 0)
            .OrderByDescending(pair => pair.Score)
            .ThenByDescending(pair => pair.Record.CreatedAt)
            .Take(Math.Max(1, limit))
            .Select(pair => new MemoryRecallHit
            {
                Summary = $"{pair.Record.SourceType} · {Trim(pair.Record.Content, 220)}",
                SourceLabel = pair.Record.SourceLabel,
                Timestamp = pair.Record.CreatedAt,
                MatchReason = pair.Record.DeepArchived ? "deep archive" : "raw archive"
            })
            .ToList();

        return hits;
    }

    public string BuildDirective(
        string prompt,
        MemoryVaultSnapshot snapshot,
        MemoryVaultPolicy policy)
    {
        var working = snapshot.RawRecords
            .Where(record => !record.DeepArchived)
            .OrderByDescending(record => record.CreatedAt)
            .Take(policy.RetrievalDepth)
            .Select(record => $"- [{record.SourceType}] {Trim(record.Content, 180)}");
        var compacted = snapshot.CompactedRecords
            .OrderByDescending(record => record.CreatedAt)
            .Take(Math.Max(2, policy.RetrievalDepth))
            .Select(record => $"- {record.Title}: {Trim(record.Summary, 180)}");

        var digest = $"""
            {prompt}

            ACTIVE MEMORY MANAGEMENT
            Hardware tier: {policy.HardwareTier}
            Context budget: {policy.ContextBudgetTokens} tokens
            Compaction threshold: {policy.CompactionThresholdTokens} tokens
            Archive search mode: {policy.ArchiveSearchMode}
            Estimated token pressure: {snapshot.LastTokenPressure}

            L1 Working Memory
            {(working.Any() ? string.Join("\n", working) : "- none")}

            L2 Compacted Context
            {(compacted.Any() ? string.Join("\n", compacted) : "- none")}

            L3 Local Encrypted Archive
            - raw records: {snapshot.RawRecords.Count}
            - compacted records: {snapshot.CompactedRecords.Count}
            - if detail is missing, recall raw memory from the local archive before finalizing the answer.
            """;

        return Trim(digest, Math.Max(1_200, policy.ContextBudgetTokens / 3));
    }

    private static void UpsertRawRecord(
        MemoryVaultSnapshot snapshot,
        string recordId,
        string sourceType,
        string sourceLabel,
        IReadOnlyList<string> tags,
        string content,
        DateTimeOffset createdAt)
    {
        var existing = snapshot.RawRecords.FirstOrDefault(record => record.RecordId == recordId);
        if (existing is not null)
        {
            existing.SourceType = sourceType;
            existing.SourceLabel = sourceLabel;
            existing.Tags = tags.Distinct(StringComparer.OrdinalIgnoreCase).Take(8).ToList();
            existing.Content = Trim(content, 1_800);
            existing.CreatedAt = createdAt;
            return;
        }

        snapshot.RawRecords.Add(new MemoryVaultRawRecord
        {
            RecordId = recordId,
            SourceType = sourceType,
            SourceLabel = sourceLabel,
            Tags = tags.Distinct(StringComparer.OrdinalIgnoreCase).Take(8).ToList(),
            Content = Trim(content, 1_800),
            CreatedAt = createdAt
        });
    }

    private static MemoryVaultSnapshot CompactOldestRecords(
        MemoryVaultSnapshot snapshot,
        MemoryVaultPolicy policy,
        string reason)
    {
        var activeRaw = snapshot.RawRecords
            .Where(record => !record.DeepArchived)
            .OrderBy(record => record.CreatedAt)
            .ToList();
        var keepCount = Math.Max(10, policy.RetrievalDepth * 3);
        var toCompact = activeRaw.Take(Math.Max(0, activeRaw.Count - keepCount)).Take(32).ToList();
        if (toCompact.Count == 0)
        {
            snapshot.LastCompactionReason = reason;
            snapshot.LastArchiveMode = "no_op";
            snapshot.LastCompactedAt = DateTimeOffset.UtcNow;
            return snapshot;
        }

        var grouped = toCompact
            .GroupBy(record => record.SourceType)
            .Select(group =>
            {
                var details = group
                    .OrderByDescending(record => record.CreatedAt)
                    .Take(6)
                    .Select(record => Trim(record.Content, 120));
                return $"{group.Key}: {string.Join(" | ", details)}";
            });
        var summary = "Preserved facts, approvals, dependencies, status, and recent artifacts from archived raw context. " +
            string.Join(" || ", grouped);

        snapshot.CompactedRecords.Insert(0, new MemoryVaultCompactedRecord
        {
            RecordId = $"compact:{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}",
            Title = $"Compacted {toCompact.Count} raw records",
            Summary = Trim(summary, 2_200),
            SourceRecordIds = toCompact.Select(record => record.RecordId).ToList(),
            CreatedAt = DateTimeOffset.UtcNow,
            TriggerReason = reason
        });

        foreach (var record in toCompact)
        {
            record.DeepArchived = true;
        }

        snapshot.LastCompactionReason = reason;
        snapshot.LastArchiveMode = "compacted";
        snapshot.LastCompactedAt = DateTimeOffset.UtcNow;
        snapshot.LastTokenPressure = Math.Max(0, snapshot.LastTokenPressure - (policy.CompactionThresholdTokens / 4));
        TrimSnapshot(snapshot);
        return snapshot;
    }

    private static void TrimSnapshot(MemoryVaultSnapshot snapshot)
    {
        snapshot.RawRecords = snapshot.RawRecords
            .OrderByDescending(record => record.CreatedAt)
            .Take(8_000)
            .ToList();
        snapshot.CompactedRecords = snapshot.CompactedRecords
            .OrderByDescending(record => record.CreatedAt)
            .Take(600)
            .ToList();
        snapshot.ArtifactRecords = snapshot.ArtifactRecords
            .OrderByDescending(record => record.CreatedAt)
            .Take(600)
            .ToList();
    }

    private static int EstimateTokens(int chars) => Math.Max(1, chars / 4);

    private static string Trim(string value, int maxChars)
    {
        var collapsed = string.Join(" ", (value ?? string.Empty)
            .Split(['\r', '\n', '\t'], StringSplitOptions.RemoveEmptyEntries))
            .Trim();
        if (collapsed.Length <= maxChars)
        {
            return collapsed;
        }
        return collapsed[..Math.Max(0, maxChars - 3)] + "...";
    }

    private static byte[] EncryptEnvelope(byte[] plaintext)
    {
        var cipher = ProtectedData.Protect(plaintext, Entropy, DataProtectionScope.CurrentUser);
        var output = new byte[EnvelopeHeader.Length + cipher.Length];
        Buffer.BlockCopy(EnvelopeHeader, 0, output, 0, EnvelopeHeader.Length);
        Buffer.BlockCopy(cipher, 0, output, EnvelopeHeader.Length, cipher.Length);
        return output;
    }

    private static byte[]? TryDecryptEnvelope(byte[] fileBytes)
    {
        if (fileBytes.Length <= EnvelopeHeader.Length)
        {
            return null;
        }
        if (!fileBytes.AsSpan(0, EnvelopeHeader.Length).SequenceEqual(EnvelopeHeader))
        {
            return null;
        }

        try
        {
            var protectedPayload = new byte[fileBytes.Length - EnvelopeHeader.Length];
            Buffer.BlockCopy(fileBytes, EnvelopeHeader.Length, protectedPayload, 0, protectedPayload.Length);
            return ProtectedData.Unprotect(protectedPayload, Entropy, DataProtectionScope.CurrentUser);
        }
        catch
        {
            return null;
        }
    }
}
