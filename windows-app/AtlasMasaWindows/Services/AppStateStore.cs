using AtlasMasaWindows.Models;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AtlasMasaWindows.Services;

public sealed class AppStateStore
{
    private const string FileName = "atlas_windows_state_v1.json";
    private static readonly byte[] EnvelopeHeader = Encoding.UTF8.GetBytes("ATLASWIN1");
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("atlas/windows/state/v1");
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

            var fileBytes = await File.ReadAllBytesAsync(_filePath, cancellationToken);
            var plaintext = TryDecryptEnvelope(fileBytes) ?? fileBytes;
            var data = JsonSerializer.Deserialize<AtlasDataEnvelope>(plaintext, _jsonOptions);
            if (data != null)
            {
                return data;
            }
            return new AtlasDataEnvelope();
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
            var plaintext = JsonSerializer.SerializeToUtf8Bytes(envelope, _jsonOptions);
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
            // Legacy plaintext state before encryption rollout.
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
