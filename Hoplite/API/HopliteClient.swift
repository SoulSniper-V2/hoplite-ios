import Foundation

nonisolated struct APIError: LocalizedError, Sendable, Equatable {
    var status: Int
    var code: String
    var requestId: String?
    var retryAfter: Int?

    var errorDescription: String? {
        switch code {
        case "auth_required", "invalid_api_key", "unauthorized": "Your session isn't valid anymore. Sign in again."
        case "rate_limited": "Hoplite is rate limiting this key. Try again in \(retryAfter ?? 60)s."
        case "insufficient_permissions", "forbidden": "This credential doesn't have permission for that. Sign in as a workspace owner or use a key with that scope."
        case "service_credential_required": "Only service-account keys can do that."
        case "platform_inference_credits_exhausted", "insufficient_credits": "The workspace is out of credits. Add credits on hoplite.sh or wait for the next reset."
        case "project_not_found", "thread_not_found", "not_found": "That resource isn't available in this workspace."
        case "network": "Can't reach Hoplite. Check your connection."
        default: code.replacingOccurrences(of: "_", with: " ").capitalizedFirst
        }
    }

    var isAuthFailure: Bool { status == 401 }
}

nonisolated enum Credential: Sendable, Equatable {
    case apiKey(String)
    case oauth(accessToken: String)

    func apply(to request: inout URLRequest) {
        switch self {
        case .apiKey(let key): request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        case .oauth(let token): request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}

/// Thin, typed wrapper over the Hoplite v1 REST API (https://hoplite.sh/docs/api).
nonisolated final class HopliteClient: Sendable {
    static let production = URL(string: "https://api.hoplite.sh")!

    let baseURL: URL
    private let credential: @Sendable () async throws -> Credential
    private let session: URLSession

    init(baseURL: URL = HopliteClient.production, credential: @escaping @Sendable () async throws -> Credential) {
        self.baseURL = baseURL
        self.credential = credential
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = ["Accept": "application/json", "User-Agent": "Hoplite-iOS/1.0"]
        self.session = URLSession(configuration: config)
    }

    // MARK: Request plumbing

    private func makeRequest(_ method: String, _ path: String, query: [String: String?] = [:], idempotent: Bool) async throws -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty { components.queryItems = items.sorted { $0.name < $1.name } }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        try await credential().apply(to: &request)
        if idempotent { request.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key") }
        return request
    }

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:], as type: T.Type = T.self) async throws -> T {
        let request = try await makeRequest("GET", path, query: query, idempotent: false)
        return try await perform(request)
    }

    func send<T: Decodable>(_ method: String, _ path: String, query: [String: String?] = [:], body: [String: Any]? = nil, as type: T.Type = T.self) async throws -> T {
        var request = try await makeRequest(method, path, query: query, idempotent: true)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await perform(request)
    }

    /// Raw bytes for non-JSON responses (transcript markdown, attachment images).
    func data(_ path: String, query: [String: String?] = [:], accept: String) async throws -> Data {
        var request = try await makeRequest("GET", path, query: query, idempotent: false)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let http = response as! HTTPURLResponse
        guard (200..<300).contains(http.statusCode) else { throw Self.error(from: data, response: http) }
        return data
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError(status: 0, code: "network")
        }
        let http = response as! HTTPURLResponse
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(from: data, response: http)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("Decode failure \(request.url?.path() ?? ""):", error)
            #endif
            throw APIError(status: http.statusCode, code: "unexpected_response", requestId: http.value(forHTTPHeaderField: "x-request-id"))
        }
    }

    static func error(from data: Data, response: HTTPURLResponse) -> APIError {
        struct Body: Decodable { var error: String? }
        let code = (try? JSONDecoder().decode(Body.self, from: data))?.error ?? "http_\(response.statusCode)"
        return APIError(
            status: response.statusCode,
            code: code,
            requestId: response.value(forHTTPHeaderField: "x-request-id"),
            retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
        )
    }

    // MARK: Event stream

    /// Streams `GET /api/events/stream`. Reconnects with `Last-Event-ID` until cancelled.
    func events(projectId: String? = nil, threadId: String? = nil) -> AsyncStream<StreamFrame> {
        AsyncStream { continuation in
            let task = Task {
                var cursor: String?
                var backoff: UInt64 = 1
                while !Task.isCancelled {
                    do {
                        var request = try await makeRequest("GET", "/api/events/stream", query: ["projectId": projectId, "threadId": threadId], idempotent: false)
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        request.timeoutInterval = 120
                        if let cursor { request.setValue(cursor, forHTTPHeaderField: "Last-Event-ID") }
                        let (bytes, response) = try await session.bytes(for: request)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                            if (response as? HTTPURLResponse)?.statusCode == 410 { cursor = nil }
                            throw APIError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, code: "stream")
                        }
                        backoff = 1
                        var parser = SSEParser()
                        for try await line in bytes.lines {
                            if let message = parser.consume(line) {
                                if let id = message.id { cursor = id }
                                if let frame = SSEParser.frame(from: message) { continuation.yield(frame) }
                            }
                        }
                    } catch {
                        if Task.isCancelled { break }
                    }
                    try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                    backoff = min(backoff * 2, 30)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Minimal Server-Sent Events line parser. `URLSession.AsyncBytes.lines` drops empty
/// lines, so a frame is dispatched when the next `id:`/`event:` field starts or when `data:` completes JSON.
nonisolated struct SSEParser {
    struct Message: Equatable {
        var id: String?
        var event: String?
        var data: String
    }

    private var id: String?
    private var event: String?
    private var data: [String] = []

    mutating func consume(_ line: String) -> Message? {
        if line.isEmpty { return flush() }
        if line.hasPrefix(":") { return Message(id: nil, event: "heartbeat", data: "") }
        let (field, value) = Self.split(line)
        switch field {
        case "id":
            let pending = data.isEmpty ? nil : flush()
            id = value
            return pending
        case "event":
            let pending = data.isEmpty ? nil : flush()
            event = value
            return pending
        case "data":
            data.append(value)
            let joined = data.joined(separator: "\n")
            return (try? JSONSerialization.jsonObject(with: Data(joined.utf8))) != nil ? flush() : nil
        default:
            return nil
        }
    }

    private mutating func flush() -> Message? {
        defer { id = nil; event = nil; data = [] }
        guard !data.isEmpty || event != nil else { return nil }
        return Message(id: id, event: event, data: data.joined(separator: "\n"))
    }

    private static func split(_ line: String) -> (String, String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, "") }
        var value = line[line.index(after: colon)...]
        if value.first == " " { value = value.dropFirst() }
        return (String(line[..<colon]), String(value))
    }

    static func frame(from message: Message) -> StreamFrame? {
        let event = message.event ?? ""
        if event == "heartbeat" || event == "ping" { return .heartbeat }
        guard let json = try? JSONSerialization.jsonObject(with: Data(message.data.utf8)) as? [String: Any] else { return nil }

        if event.hasPrefix("draft") || json["streamId"] != nil || json["revision"] != nil {
            let messageId = (json["messageId"] as? String) ?? (json["id"] as? String) ?? ""
            if event == "draft.removed" || json["removed"] as? Bool == true { return .draftRemoved(messageId: messageId) }
            let draft = (json["draft"] as? [String: Any]) ?? json
            let content = (draft["content"] as? String) ?? (draft["text"] as? String) ?? (draft["delta"] as? String) ?? ""
            let kind = (draft["kind"] as? String).flatMap(MessageKind.init(rawValue:)) ?? .chat
            let revision = (json["revision"] as? Int) ?? Int(json["revision"] as? String ?? "") ?? 0
            return .draft(DraftFrame(messageId: messageId, revision: revision, content: content, kind: kind))
        }
        guard let decoded = try? JSONDecoder().decode(PublicEvent.self, from: Data(message.data.utf8)) else { return nil }
        return .event(decoded)
    }
}

extension String {
    nonisolated var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
