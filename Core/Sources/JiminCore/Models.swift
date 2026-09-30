import Foundation

public enum Persona: String, CaseIterable, Codable, Identifiable, Sendable {
    case playful, gentle, direct
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .playful: return "다정하고 장난스러운"
        case .gentle: return "차분하고 다정한"
        case .direct: return "직설적이고 장난스러운"
        }
    }
    public var subtitle: String {
        switch self {
        case .playful: return "예상 못 한 이야기, 웃으면서"
        case .gentle: return "서두르지 않고 네 곁에서"
        case .direct: return "돌려 말하지 않는 엉뚱함"
        }
    }
    public var sample: String {
        switch self {
        case .playful: return "자기야, 우리 집에 손바닥만 한 용이 들어오면 이름부터 지을까, 숨길 곳부터 찾을까?"
        case .gentle: return "오늘을 아이스크림 맛으로 표현하면 무슨 맛이야? 네가 고르는 맛이 궁금해."
        case .direct: return "갑자기 궁금해졌는데, 짝 잃은 양말은 자유로운 영혼일까, 그냥 길치일까?"
        }
    }
}

public struct CharacterProfile: Codable, Equatable, Sendable {
    public var name: String = "지민"
    public var persona: Persona = .playful
    public var voice: String = "marin"
    public var nickname: String = "자기야"
    public init() {}
}

public struct ConfirmedMemory: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var confirmedAt: Date
    public init(id: UUID = UUID(), text: String, confirmedAt: Date = Date()) {
        self.id = id; self.text = text; self.confirmedAt = confirmedAt
    }
}

public struct MemoryProposal: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let proposedAt: Date
    public init(text: String, now: Date = Date()) {
        id = UUID(); self.text = text; proposedAt = now
    }
}

public struct MonitoredApp: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    /// Apple's opaque token never leaves the device.
    public let tokenData: Data
    public var dailyMinutes: Int
    public init(id: UUID = UUID(), tokenData: Data, dailyMinutes: Int = 30) {
        self.id = id; self.tokenData = tokenData; self.dailyMinutes = dailyMinutes
    }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var profile = CharacterProfile()
    public var proactiveEnabled = true
    public var retryEnabled = true
    public var retryMinutes = 20
    public var pausedDay: String?
    public var startedAt = Date()
    public var onboardingComplete = false
    public var memories: [ConfirmedMemory] = []
    public init() {}
}

public enum CallOutcome: String, Codable, Sendable {
    case requested, ringing, answered, voiceConnected, declined, unanswered, failed, ended
    public var isTerminal: Bool { [.declined, .unanswered, .failed, .ended].contains(self) }
    public var wasAnswered: Bool { [.answered, .voiceConnected, .ended].contains(self) }
}

public struct CallAttempt: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let appID: UUID
    public let day: String
    public let ordinal: Int
    public let requestedAt: Date
    public var outcome: CallOutcome
    public var answeredAt: Date?
    public var finishedAt: Date?
}

public struct AppDayLedger: Codable, Equatable, Sendable {
    public var firstObserved = false
    public var attemptIDs: [UUID] = []
    public var answered = false
    public var retryArmedAt: Date?
    public var retryMinutes: Int?
    public var retryMonitorRegisteredAt: Date?
    public init() {}
}

public struct LocalDetection: Codable, Identifiable, Sendable {
    public let id: UUID
    public let appID: UUID
    public let at: Date
    public let kind: ThresholdKind
    public let result: String
}

public struct SharedState: Codable, Sendable {
    public var preferences = AppPreferences()
    public var apps: [MonitoredApp] = []
    public var knownApps: [MonitoredApp] = []
    public var day = ""
    public var ledgers: [String: AppDayLedger] = [:]
    public var attempts: [CallAttempt] = []
    public var detections: [LocalDetection] = []
    public var activeCallID: UUID?
    public var busyUntil: Date?
    public var screenTimeAuthorized = false
    public var lastMonitorError: String?
    public var callHistory: [LocalCallRecord] = []
    public init() {}
}

public struct LocalCallRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let characterName: String
    public let startedAt: Date
    public var outcome: CallOutcome
    public var voiceConnectedAt: Date?
    public var finishedAt: Date?
    public var arrivalDelaySeconds: Double?
    public init(id: UUID, characterName: String, startedAt: Date, outcome: CallOutcome = .requested) {
        self.id = id; self.characterName = characterName; self.startedAt = startedAt; self.outcome = outcome
    }
}

public enum ThresholdKind: String, Codable, Sendable { case first, retry }

public enum DetectionDecision: Equatable, Sendable {
    case request(UUID)
    case skip(String)
}
