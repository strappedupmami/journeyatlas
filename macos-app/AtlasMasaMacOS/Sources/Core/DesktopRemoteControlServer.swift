import Foundation
import Network

final class DesktopRemoteControlServer {
    struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    struct Response {
        let statusCode: Int
        let jsonObject: Any
    }

    private let port: UInt16
    private let handler: @Sendable (Request) async -> Response
    private var listener: NWListener?

    init(port: UInt16, handler: @escaping @Sendable (Request) async -> Response) {
        self.port = port
        self.handler = handler
    }

    func start() throws {
        guard listener == nil else { return }
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: DispatchQueue(label: "com.atlasmasa.macos.remote-control"))
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "com.atlasmasa.macos.remote-client"))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_000_000) { [weak self] data, _, _, _ in
            guard let self, let data else {
                connection.cancel()
                return
            }

            Task {
                let response = await self.parseAndHandle(data: data)
                self.write(response: response, to: connection)
            }
        }
    }

    private func parseAndHandle(data: Data) async -> Response {
        guard let text = String(data: data, encoding: .utf8),
              let headerRange = text.range(of: "\r\n\r\n")
        else {
            return Response(statusCode: 400, jsonObject: ["error": "invalid_request"])
        }

        let headerText = String(text[..<headerRange.lowerBound])
        let bodyText = String(text[headerRange.upperBound...])
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return Response(statusCode: 400, jsonObject: ["error": "missing_request_line"])
        }

        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count >= 2 else {
            return Response(statusCode: 400, jsonObject: ["error": "invalid_request_line"])
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        return await handler(Request(
            method: String(requestParts[0]).uppercased(),
            path: String(requestParts[1]),
            headers: headers,
            body: Data(bodyText.utf8)
        ))
    }

    private func write(response: Response, to connection: NWConnection) {
        let bodyData: Data
        if let data = try? JSONSerialization.data(withJSONObject: response.jsonObject, options: []) {
            bodyData = data
        } else {
            bodyData = Data("{\"error\":\"encoding_failed\"}".utf8)
        }

        let header = """
        HTTP/1.1 \(response.statusCode) \(reasonPhrase(response.statusCode))\r
        Content-Type: application/json; charset=utf-8\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r
        """
        var packet = Data(header.utf8)
        packet.append(bodyData)
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func reasonPhrase(_ statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        default: return "OK"
        }
    }
}
