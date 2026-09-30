import Foundation
import JiminCore

struct CallEnvelope: Decodable {
    let id: UUID
    let displayName: String
    let createdAt: Date
    let expiresAt: Date
    let status: String
    let delivery: String
    let character: CharacterProfile?
    let instructions: String?
}

enum BackendClient {
    struct Health: Decodable { let ok: Bool; let voiceConfigured: Bool }
    static func health() async throws -> Health {
        try decoder.decode(Health.self, from: await request("health", method: "GET"))
    }
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .custom { value in
        let text = try value.singleValueContainer().decode(String.self)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        throw DecodingError.dataCorrupted(.init(codingPath: value.codingPath, debugDescription: "Invalid server date"))
    }; return d }()

    static func register(baseURL: URL, pairingCode: String) async throws -> APIConnection {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/devices"))
        request.httpMethod = "POST"; request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(pairingCode, forHTTPHeaderField: "X-Pairing-Code")
        let data = try await perform(request)
        struct Result: Decodable { let deviceId: String; let token: String }
        let result = try decoder.decode(Result.self, from: data)
        return APIConnection(baseURL: baseURL, deviceID: result.deviceId, token: result.token)
    }
    static func request(_ path: String, method: String = "POST", body: Any? = nil) async throws -> Data {
        guard let connection = try SecureConnectionStore.read() else { throw APIError("서버를 먼저 연결해 주세요. 설정의 ‘시험 서버 연결’에서 연결할 수 있어요.") }
        var request = URLRequest(url: connection.baseURL.appendingPathComponent(path)); request.httpMethod = method
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return try await perform(request)
    }
    static func sync(_ prefs: AppPreferences) async throws {
        _ = try await request("v1/device/profile", method: "PUT", body: profileBody(prefs))
    }
    static func profileBody(_ prefs: AppPreferences) -> [String: Any] {
        ["character": ["name": prefs.profile.name, "persona": prefs.profile.persona.rawValue,
                        "voice": prefs.profile.voice, "nickname": prefs.profile.nickname],
         "memories": prefs.memories.map { ["id": $0.id.uuidString, "text": $0.text, "confirmedAt": ISO8601DateFormatter().string(from: $0.confirmedAt)] },
         "proactiveEnabled": prefs.proactiveEnabled, "pausedDay": prefs.pausedDay as Any? ?? NSNull(),
         "timeZone": TimeZone.current.identifier]
    }
    static func manualCall() async throws -> CallEnvelope {
        let data = try await request("v1/calls", body: ["requestId": UUID().uuidString, "mode": "manual", "createdAt": ISO8601DateFormatter().string(from: Date())])
        return try decoder.decode(CallEnvelope.self, from: data)
    }
    static func call(_ id: UUID) async throws -> CallEnvelope {
        try decoder.decode(CallEnvelope.self, from: await request("v1/calls/\(id.uuidString)", method: "GET"))
    }
    static func result(_ id: UUID, _ outcome: CallOutcome) async throws {
        _ = try await request("v1/calls/\(id.uuidString)/result", body: ["status": outcome.rawValue])
    }
    static func liveUsage(_ id: UUID, seconds: Double) async throws {
        _ = try await request("v1/calls/\(id.uuidString)/usage", body: ["seconds": seconds])
    }
    static func session(_ id: UUID, offer: String) async throws -> String {
        let data = try await request("v1/calls/\(id.uuidString)/session", body: ["sdp": offer])
        guard let sdp = String(data: data, encoding: .utf8), sdp.hasPrefix("v=0") else { throw APIError("음성 연결 정보가 올바르지 않습니다.") }
        return sdp
    }
    private static func perform(_ request: URLRequest) async throws -> Data {
        var r = request; r.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: r)
        guard let response = response as? HTTPURLResponse else { throw APIError("서버 응답을 확인하지 못했습니다.") }
        guard (200..<300).contains(response.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            let code = object?["error"] ?? "http_\(response.statusCode)"
            let messages = ["openai_not_configured": "서버에 OpenAI API 키가 아직 설정되지 않았어요. 실제 통화는 키를 넣은 뒤 시험할 수 있어요.",
                "openai_http_401": "OpenAI가 서버의 API 키를 받아들이지 않았어요. Mac의 비공개 설정 화면에서 키를 다시 확인해 주세요.",
                "openai_http_403": "이 계정에서 음성 API 사용이 거절됐어요. OpenAI의 프로젝트 권한과 이용 가능 상태를 확인해 주세요.",
                "openai_http_404": "설정한 음성 모델에 접근하지 못했어요. 서버의 모델 설정과 OpenAI 계정을 확인해 주세요.",
                "openai_http_429": "OpenAI API 잔액이나 사용·요청 한도에 걸렸어요. OpenAI 계정 상태를 확인한 뒤 다시 시험해 주세요.",
                "openai_connection_failed": "서버가 OpenAI에 연결하지 못했어요. Mac의 인터넷 연결을 확인해 주세요.",
                "openai_invalid_session": "OpenAI의 음성 연결 응답을 확인하지 못했어요. 잠시 후 다시 시험해 주세요.",
                "pairing_code_invalid": "연결 코드가 맞지 않아요. 서버의 연결 코드를 확인해 주세요.",
                "authentication_required": "서버 연결이 만료되었어요. 다시 연결해 주세요.",
                "apple_approval_pending": "Apple의 허용 여부가 확인되기 전에는 자동 전화를 보낼 수 없어요.",
                "already_in_call": "이미 진행 중인 전화가 있어요. 먼저 통화를 끝내 주세요.",
                "stale_request": "너무 오래된 전화 요청이라 취소했어요.",
                "rate_limited": "잠깐 쉬었다가 다시 시도해 주세요."]
            throw APIError(messages[code] ?? "연결에 문제가 생겼어요. 서버 상태를 확인해 주세요. (\(code))")
        }
        return data
    }
    struct APIError: LocalizedError { let message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { message } }
}
