import Foundation

struct DemoSession: Decodable, Sendable {
    var accessToken: String
    var role: String
    var displayName: String
    var patientId: UUID
    var patientName: String
}

struct ReadingPoint: Decodable, Identifiable, Sendable {
    var index: Int
    var run: Int
    var sequence: Int
    var at: Date
    var heartRateBpm: Double?
    var motionRms: Double?
    var score: Double?
    var quality: String

    var id: Int { index }
}

struct DemoEvent: Decodable, Identifiable, Equatable, Sendable {
    var id: UUID
    var kind: String
    var alarmStatus: String
    var reviewStatus: String
    var startedAt: Date
    var endedAt: Date?
    var deadlineAt: Date?
    var acknowledgedAt: Date?
    var reason: String
    var scorePeak: Double?
    var synthetic: Bool
}

struct LiveSnapshot: Decodable, Sendable {
    var patientName: String
    var sleepWindow: String
    var monitoring: String
    var monitoringTitle: String
    var detail: String
    var wearableConnected: Bool
    var wearableLabel: String
    var baselineHr: Double
    var modelThreshold: Double?
    var demoCase: String?
    var synthetic: Bool
    var readings: [ReadingPoint]
    var activeEvent: DemoEvent?
}

struct EventList: Decodable, Sendable {
    var events: [DemoEvent]
}

enum SomniaAPIError: Error {
    case offline
    case message(String)
}

struct SomniaAPI {
    var baseURL: URL
    var token: String?

    func enter(role: String) async throws -> DemoSession {
        try await send(path: "/api/v1/demo/session", method: "POST", body: ["role": role], authorize: false)
    }

    func live() async throws -> LiveSnapshot {
        try await send(path: "/api/v1/live", method: "GET", body: Optional<[String: String]>.none, authorize: true)
    }

    func run(caseName: String) async throws -> LiveSnapshot {
        try await send(path: "/api/v1/demo/runs", method: "POST", body: ["case": caseName], authorize: true)
    }

    func events() async throws -> [DemoEvent] {
        let list: EventList = try await send(path: "/api/v1/events", method: "GET", body: Optional<[String: String]>.none, authorize: true)
        return list.events
    }

    func acknowledge(id: UUID) async throws -> DemoEvent {
        try await send(path: "/api/v1/events/\(id.uuidString)/acknowledge", method: "POST", body: Optional<[String: String]>.none, authorize: true)
    }

    func reset() async throws -> LiveSnapshot {
        try await send(path: "/api/v1/demo/reset", method: "POST", body: Optional<[String: String]>.none, authorize: true)
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        body: [String: String]?,
        authorize: Bool
    ) async throws -> Response {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorize, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SomniaAPIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw SomniaAPIError.message("The server response was unreadable.") }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw SomniaAPIError.message(message(from: data) ?? "The server returned \(http.statusCode).")
        }
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw SomniaAPIError.message("The app could not read the server data.")
        }
    }

    private func endpoint(_ path: String) -> URL {
        var root = baseURL.absoluteString
        if root.hasSuffix("/") { root.removeLast() }
        return URL(string: root + path)!
    }

    private func message(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (object["detail"] as? String) ?? (object["message"] as? String)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = parseDate(value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: value)
        }
        return decoder
    }()

    private static func parseDate(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}
