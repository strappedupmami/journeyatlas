using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace AtlasMasaWindows.Services;

public sealed class DesktopRemoteControlServer : IAsyncDisposable
{
    public sealed record RemoteRequest(
        string Method,
        string Path,
        IReadOnlyDictionary<string, string> Headers,
        string Body,
        IPEndPoint? RemoteEndPoint);

    public sealed record RemoteResponse(
        int StatusCode,
        object Payload);

    private readonly int _port;
    private readonly Func<RemoteRequest, Task<RemoteResponse>> _handler;
    private readonly CancellationTokenSource _cts = new();
    private readonly JsonSerializerOptions _jsonOptions = new(JsonSerializerDefaults.Web);
    private TcpListener? _listener;
    private Task? _loopTask;

    public DesktopRemoteControlServer(int port, Func<RemoteRequest, Task<RemoteResponse>> handler)
    {
        _port = port;
        _handler = handler;
    }

    public void Start()
    {
        if (_listener is not null)
        {
            return;
        }

        _listener = new TcpListener(IPAddress.Any, _port);
        _listener.Start();
        _loopTask = Task.Run(() => AcceptLoopAsync(_cts.Token));
    }

    private async Task AcceptLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            TcpClient? client = null;
            try
            {
                client = await _listener!.AcceptTcpClientAsync(cancellationToken);
                _ = Task.Run(() => HandleClientAsync(client, cancellationToken), cancellationToken);
            }
            catch (OperationCanceledException)
            {
                client?.Dispose();
                break;
            }
            catch
            {
                client?.Dispose();
            }
        }
    }

    private async Task HandleClientAsync(TcpClient client, CancellationToken cancellationToken)
    {
        using (client)
        {
            await using var stream = client.GetStream();
            using var reader = new StreamReader(stream, Encoding.UTF8, leaveOpen: true);
            var requestLine = await reader.ReadLineAsync(cancellationToken);
            if (string.IsNullOrWhiteSpace(requestLine))
            {
                return;
            }

            var parts = requestLine.Split(' ', 3, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length < 2)
            {
                await WriteResponseAsync(stream, 400, new { error = "invalid_request_line" }, cancellationToken);
                return;
            }

            var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            while (true)
            {
                var line = await reader.ReadLineAsync(cancellationToken);
                if (string.IsNullOrEmpty(line))
                {
                    break;
                }

                var separator = line.IndexOf(':');
                if (separator <= 0)
                {
                    continue;
                }

                headers[line[..separator].Trim()] = line[(separator + 1)..].Trim();
            }

            var contentLength = 0;
            if (headers.TryGetValue("Content-Length", out var contentLengthRaw))
            {
                int.TryParse(contentLengthRaw, out contentLength);
                contentLength = Math.Clamp(contentLength, 0, 1_000_000);
            }

            var body = string.Empty;
            if (contentLength > 0)
            {
                var buffer = new char[contentLength];
                var totalRead = 0;
                while (totalRead < contentLength)
                {
                    var read = await reader.ReadAsync(buffer.AsMemory(totalRead, contentLength - totalRead), cancellationToken);
                    if (read <= 0)
                    {
                        break;
                    }
                    totalRead += read;
                }
                body = new string(buffer, 0, totalRead);
            }

            RemoteResponse response;
            try
            {
                response = await _handler(new RemoteRequest(
                    Method: parts[0].Trim().ToUpperInvariant(),
                    Path: parts[1].Trim(),
                    Headers: headers,
                    Body: body,
                    RemoteEndPoint: client.Client.RemoteEndPoint as IPEndPoint));
            }
            catch (Exception ex)
            {
                response = new RemoteResponse(500, new { error = "server_error", detail = ex.Message });
            }

            await WriteResponseAsync(stream, response.StatusCode, response.Payload, cancellationToken);
        }
    }

    private async Task WriteResponseAsync(NetworkStream stream, int statusCode, object payload, CancellationToken cancellationToken)
    {
        var body = JsonSerializer.Serialize(payload, _jsonOptions);
        var bodyBytes = Encoding.UTF8.GetBytes(body);
        var header =
            $"HTTP/1.1 {statusCode} {ReasonPhrase(statusCode)}\r\n" +
            "Content-Type: application/json; charset=utf-8\r\n" +
            $"Content-Length: {bodyBytes.Length}\r\n" +
            "Connection: close\r\n\r\n";
        var headerBytes = Encoding.ASCII.GetBytes(header);
        await stream.WriteAsync(headerBytes, cancellationToken);
        await stream.WriteAsync(bodyBytes, cancellationToken);
        await stream.FlushAsync(cancellationToken);
    }

    private static string ReasonPhrase(int statusCode) => statusCode switch
    {
        200 => "OK",
        400 => "Bad Request",
        401 => "Unauthorized",
        404 => "Not Found",
        405 => "Method Not Allowed",
        500 => "Internal Server Error",
        _ => "OK"
    };

    public async ValueTask DisposeAsync()
    {
        _cts.Cancel();
        try
        {
            _listener?.Stop();
        }
        catch
        {
            // ignore shutdown exceptions
        }

        if (_loopTask is not null)
        {
            try
            {
                await _loopTask;
            }
            catch
            {
                // ignore shutdown exceptions
            }
        }

        _cts.Dispose();
    }
}
