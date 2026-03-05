using AtlasMasaWindows.Models;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AtlasMasaWindows.Services;

public sealed class RustReasoningBridge
{
    private readonly string? _binaryPath;
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public bool Enabled => _binaryPath is not null;

    public string StatusLine => Enabled
        ? $"Rust local reasoner bridge enabled: {_binaryPath}"
        : "Rust local reasoner bridge unavailable. Using managed fallback. Set ATLAS_RUST_REASONER_BIN to enable.";

    public RustReasoningBridge()
    {
        _binaryPath = ResolveBinaryPath();
    }

    public async Task<RustInferencePolicy?> TrySelectPolicyAsync(
        string platform,
        string task,
        int cpuCores,
        long memoryGb,
        bool highPerformance,
        string? preferredModel,
        IReadOnlyList<string>? modelCatalog,
        CancellationToken cancellationToken = default)
    {
        if (!Enabled)
        {
            return null;
        }

        var requestJson = JsonSerializer.Serialize(new RustPolicyRequest
        {
            Platform = string.IsNullOrWhiteSpace(platform) ? "windows" : platform.Trim(),
            Task = string.IsNullOrWhiteSpace(task) ? "general" : task.Trim(),
            CpuCores = Math.Clamp(cpuCores, 1, 256),
            MemoryGb = Math.Clamp(memoryGb, 4, 2_048),
            HighPerformance = highPerformance,
            PreferredModel = preferredModel?.Trim() ?? string.Empty,
            ModelCatalog = modelCatalog?.Where(item => !string.IsNullOrWhiteSpace(item)).Select(item => item.Trim()).Distinct(StringComparer.OrdinalIgnoreCase).ToList() ?? []
        }, _jsonOptions);

        using var process = BuildProcess(arguments: ["policy"]);
        try
        {
            if (!process.Start())
            {
                return null;
            }

            await process.StandardInput.WriteAsync(requestJson.AsMemory(), cancellationToken);
            process.StandardInput.Close();

            var outputTask = process.StandardOutput.ReadToEndAsync();
            var errorTask = process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync(cancellationToken);

            var output = (await outputTask).Trim();
            _ = await errorTask;

            if (process.ExitCode != 0 || string.IsNullOrWhiteSpace(output))
            {
                return null;
            }

            var response = JsonSerializer.Deserialize<RustPolicyResponse>(output, _jsonOptions);
            if (response is null || string.IsNullOrWhiteSpace(response.SelectedModel))
            {
                return null;
            }

            return new RustInferencePolicy
            {
                SelectedModel = response.SelectedModel.Trim(),
                FallbackModels = response.FallbackModels?
                    .Where(item => !string.IsNullOrWhiteSpace(item))
                    .Select(item => item.Trim())
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .ToList() ?? [],
                ReasoningMode = string.IsNullOrWhiteSpace(response.ReasoningMode) ? "standard" : response.ReasoningMode.Trim(),
                AnalysisPasses = Math.Clamp(response.AnalysisPasses, 1, 6),
                Temperature = Math.Clamp(response.Temperature, 0.0, 0.95),
                MaxTokens = Math.Clamp(response.MaxTokens, 320, 4096),
                NumContext = Math.Clamp(response.NumContext, 2048, 131_072),
                TimeoutSeconds = Math.Clamp(response.TimeoutSeconds, 8, 180),
                HardwareTier = string.IsNullOrWhiteSpace(response.HardwareTier) ? "balanced" : response.HardwareTier.Trim(),
                StatusLine = string.IsNullOrWhiteSpace(response.StatusLine)
                    ? $"Rust policy selected {response.SelectedModel}."
                    : response.StatusLine.Trim()
            };
        }
        catch (OperationCanceledException)
        {
            TryKill(process);
            throw;
        }
        catch
        {
            TryKill(process);
            return null;
        }
    }

    public async Task<LocalReasoningOutput?> TryReasonAsync(
        string prompt,
        int notesUsed,
        CancellationToken cancellationToken = default)
    {
        if (!Enabled || string.IsNullOrWhiteSpace(prompt))
        {
            return null;
        }

        var requestJson = JsonSerializer.Serialize(new RustReasoningRequest
        {
            Prompt = prompt.Trim(),
            NotesUsed = Math.Clamp(notesUsed, 0, 16)
        }, _jsonOptions);

        using var process = BuildProcess();

        try
        {
            if (!process.Start())
            {
                return null;
            }

            await process.StandardInput.WriteAsync(requestJson.AsMemory(), cancellationToken);
            process.StandardInput.Close();

            var outputTask = process.StandardOutput.ReadToEndAsync();
            var errorTask = process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync(cancellationToken);

            var output = (await outputTask).Trim();
            _ = await errorTask; // Keep stderr drained to avoid process hangs.

            if (process.ExitCode != 0 || string.IsNullOrWhiteSpace(output))
            {
                return null;
            }

            var response = JsonSerializer.Deserialize<RustReasoningResponse>(output, _jsonOptions);
            if (response is null || string.IsNullOrWhiteSpace(response.Summary) || string.IsNullOrWhiteSpace(response.NextAction))
            {
                return null;
            }

            return new LocalReasoningOutput
            {
                Model = string.IsNullOrWhiteSpace(response.Model)
                    ? "atlas-rust-local-reasoner-v1"
                    : response.Model!,
                Summary = response.Summary.Trim(),
                NextAction = response.NextAction.Trim(),
                Confidence = Math.Clamp(response.Confidence, 0.0, 1.0),
                GeneratedAt = DateTimeOffset.UtcNow
            };
        }
        catch (OperationCanceledException)
        {
            TryKill(process);
            throw;
        }
        catch
        {
            TryKill(process);
            return null;
        }
    }

    private Process BuildProcess(IReadOnlyList<string>? arguments = null)
    {
        var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = _binaryPath!,
                UseShellExecute = false,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            }
        };
        if (arguments is not null)
        {
            foreach (var argument in arguments)
            {
                process.StartInfo.ArgumentList.Add(argument);
            }
        }
        return process;
    }

    private static void TryKill(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch
        {
            // Best effort only.
        }
    }

    private static string? ResolveBinaryPath()
    {
        var envPath = Environment.GetEnvironmentVariable("ATLAS_RUST_REASONER_BIN")?.Trim();
        if (!string.IsNullOrWhiteSpace(envPath) && File.Exists(envPath))
        {
            return envPath;
        }

        var directCandidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "atlas-rust-reasoner.exe"),
            Path.Combine(AppContext.BaseDirectory, "atlas-rust-reasoner")
        };
        foreach (var candidate in directCandidates)
        {
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        var cursor = AppContext.BaseDirectory;
        for (var i = 0; i < 9; i++)
        {
            var windowsPath = Path.Combine(cursor, "windows-app", "rust-atlas-reasoner", "target", "release", "atlas-rust-reasoner.exe");
            if (File.Exists(windowsPath))
            {
                return windowsPath;
            }

            var localPath = Path.Combine(cursor, "windows-app", "rust-atlas-reasoner", "target", "release", "atlas-rust-reasoner");
            if (File.Exists(localPath))
            {
                return localPath;
            }

            var parent = Directory.GetParent(cursor);
            if (parent is null)
            {
                break;
            }
            cursor = parent.FullName;
        }

        return null;
    }

    private sealed class RustReasoningRequest
    {
        [JsonPropertyName("prompt")]
        public string Prompt { get; set; } = string.Empty;
        [JsonPropertyName("notes_used")]
        public int NotesUsed { get; set; }
    }

    private sealed class RustPolicyRequest
    {
        [JsonPropertyName("platform")]
        public string Platform { get; set; } = "windows";
        [JsonPropertyName("task")]
        public string Task { get; set; } = "general";
        [JsonPropertyName("cpu_cores")]
        public int CpuCores { get; set; }
        [JsonPropertyName("memory_gb")]
        public long MemoryGb { get; set; }
        [JsonPropertyName("high_performance")]
        public bool HighPerformance { get; set; }
        [JsonPropertyName("preferred_model")]
        public string PreferredModel { get; set; } = string.Empty;
        [JsonPropertyName("model_catalog")]
        public List<string> ModelCatalog { get; set; } = [];
    }

    private sealed class RustPolicyResponse
    {
        [JsonPropertyName("selected_model")]
        public string? SelectedModel { get; set; }
        [JsonPropertyName("fallback_models")]
        public List<string>? FallbackModels { get; set; }
        [JsonPropertyName("reasoning_mode")]
        public string? ReasoningMode { get; set; }
        [JsonPropertyName("analysis_passes")]
        public int AnalysisPasses { get; set; }
        [JsonPropertyName("temperature")]
        public double Temperature { get; set; }
        [JsonPropertyName("max_tokens")]
        public int MaxTokens { get; set; }
        [JsonPropertyName("num_ctx")]
        public int NumContext { get; set; }
        [JsonPropertyName("timeout_seconds")]
        public int TimeoutSeconds { get; set; }
        [JsonPropertyName("hardware_tier")]
        public string? HardwareTier { get; set; }
        [JsonPropertyName("status_line")]
        public string? StatusLine { get; set; }
    }

    private sealed class RustReasoningResponse
    {
        [JsonPropertyName("model")]
        public string? Model { get; set; }
        [JsonPropertyName("summary")]
        public string Summary { get; set; } = string.Empty;
        [JsonPropertyName("next_action")]
        public string NextAction { get; set; } = string.Empty;
        [JsonPropertyName("confidence")]
        public double Confidence { get; set; }
    }
}

public sealed class RustInferencePolicy
{
    public string SelectedModel { get; init; } = "llama3.2:latest";
    public IReadOnlyList<string> FallbackModels { get; init; } = [];
    public string ReasoningMode { get; init; } = "standard";
    public int AnalysisPasses { get; init; } = 2;
    public double Temperature { get; init; } = 0.22;
    public int MaxTokens { get; init; } = 900;
    public int NumContext { get; init; } = 8192;
    public int TimeoutSeconds { get; init; } = 30;
    public string HardwareTier { get; init; } = "balanced";
    public string StatusLine { get; init; } = "Rust policy unavailable.";
}
