using AtlasMasaWindows.Models;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AtlasMasaWindows.Services;

public sealed class AppStateStore
{
    private const string FileName = "atlas_windows_state_v1.json";
    private readonly string _directory;
    private readonly string _filePath;
    private readonly string _tmpFilePath;
    private readonly JsonSerializerOptions _jsonOptions;
    private readonly SemaphoreSlim _fileLock = new(1, 1);

    public AppStateStore()
    {
        _directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Atlas",
            "Windows");
        _filePath = Path.Combine(_directory, FileName);
        _tmpFilePath = Path.Combine(_directory, $"{FileName}.tmp");
        _jsonOptions = new JsonSerializerOptions
        {
            WriteIndented = true,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            Converters = { new JsonStringEnumConverter() }
        };
    }

    public async Task<AtlasDataEnvelope> LoadAsync(CancellationToken cancellationToken = default)
    {
        await _fileLock.WaitAsync(cancellationToken);
        try
        {
            if (!File.Exists(_filePath))
            {
                return new AtlasDataEnvelope();
            }

            await using var stream = File.OpenRead(_filePath);
            var data = await JsonSerializer.DeserializeAsync<AtlasDataEnvelope>(stream, _jsonOptions, cancellationToken);
            return data ?? new AtlasDataEnvelope();
        }
        catch
        {
            return new AtlasDataEnvelope();
        }
        finally
        {
            _fileLock.Release();
        }
    }

    public async Task SaveAsync(AtlasDataEnvelope envelope, CancellationToken cancellationToken = default)
    {
        await _fileLock.WaitAsync(cancellationToken);
        try
        {
            Directory.CreateDirectory(_directory);
            envelope.LastSavedAt = DateTimeOffset.UtcNow;

            await using (var stream = File.Create(_tmpFilePath))
            {
                await JsonSerializer.SerializeAsync(stream, envelope, _jsonOptions, cancellationToken);
            }

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
}
