import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings
import JiminCore

enum ScreenTimeScheduler {
    static let daily = DeviceActivityName("jimin.daily")
    static func event(_ id: UUID, _ kind: ThresholdKind) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("\(kind.rawValue).\(id.uuidString)")
    }
    static func parse(_ event: DeviceActivityEvent.Name) -> (UUID, ThresholdKind)? {
        let parts = event.rawValue.split(separator: ".")
        guard parts.count == 2, let kind = ThresholdKind(rawValue: String(parts[0])), let id = UUID(uuidString: String(parts[1])) else { return nil }
        return (id, kind)
    }
    static func retryName(_ id: UUID) -> DeviceActivityName { DeviceActivityName("jimin.retry.\(id.uuidString)") }
    static func token(_ app: MonitoredApp) -> ApplicationToken? { try? JSONDecoder().decode(ApplicationToken.self, from: app.tokenData) }

    #if DEBUG
    static func freshActivity(_ id: UUID) -> DeviceActivityName { DeviceActivityName("jimin.fresh.\(id.uuidString)") }
    static func freshEvent(_ id: UUID) -> DeviceActivityEvent.Name { DeviceActivityEvent.Name("fresh.\(id.uuidString)") }
    static func parseFresh(_ event: DeviceActivityEvent.Name) -> UUID? {
        let parts = event.rawValue.split(separator: ".")
        guard parts.count == 2, parts[0] == "fresh" else { return nil }
        return UUID(uuidString: String(parts[1]))
    }
    static func armFreshUsageTest(_ test: FreshUsageTest, state: SharedState) throws {
        guard state.screenTimeAuthorized,
              let app = state.apps.first(where: { $0.id == test.appID }),
              let appToken = token(app) else {
            throw NSError(domain: "Jimin", code: 2, userInfo: [NSLocalizedDescriptionKey: "선택한 앱의 사용 시간 권한을 확인해 주세요."])
        }
        let calendar = Calendar.current
        var start = calendar.dateComponents([.year, .month, .day], from: test.startedAt)
        start.hour = 0; start.minute = 0; start.second = 0
        var end = start; end.hour = 23; end.minute = 59; end.second = 59
        try DeviceActivityCenter().startMonitoring(freshActivity(test.id),
            during: DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: false),
            events: [freshEvent(test.id): DeviceActivityEvent(applications: [appToken],
                threshold: DateComponents(minute: 1), includesPastActivity: false)])
    }
    #endif

    static func replaceFirstThresholds(_ state: SharedState) throws {
        let center = DeviceActivityCenter()
        guard state.screenTimeAuthorized, !state.apps.isEmpty else {
            center.stopMonitoring(); return
        }
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for app in state.apps {
            guard let token = token(app) else { continue }
            events[event(app.id, .first)] = DeviceActivityEvent(
                applications: [token], threshold: DateComponents(minute: app.dailyMinutes), includesPastActivity: true)
        }
        guard !events.isEmpty else { center.stopMonitoring(); return }
        let schedule = DeviceActivitySchedule(intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
                                             intervalEnd: DateComponents(hour: 23, minute: 59, second: 59), repeats: true)
        // Replacing this schedule recounts today's existing usage, while the ledger
        // keeps firstObserved and all attempted/answered calls intact.
        try center.startMonitoring(daily, during: schedule, events: events)
    }

    static func armMissedCallRetry(appID: UUID, now: Date = Date()) throws {
        let store = try SharedResources.store()
        let registration: (MonitoredApp, Int)? = try store.update { state in
            InterventionPolicy.rollDay(&state, now: now)
            guard state.screenTimeAuthorized, state.preferences.retryEnabled,
                  state.preferences.proactiveEnabled, state.preferences.pausedDay != state.day,
                  let app = state.apps.first(where: { $0.id == appID }),
                  var ledger = state.ledgers[appID.uuidString],
                  let armedAt = ledger.retryArmedAt, ledger.retryMonitorRegisteredAt == nil,
                  !ledger.answered else { return nil }
            ledger.retryMonitorRegisteredAt = armedAt
            state.ledgers[appID.uuidString] = ledger
            return (app, ledger.retryMinutes ?? 20)
        }
        guard let (app, minutes) = registration, let token = token(app) else { return }
        // A newly started event excludes activity BEFORE the missed-call outcome.
        // Its window still spans the full day, avoiding very short schedule errors.
        let calendar = Calendar.current
        var start = calendar.dateComponents([.year, .month, .day], from: now)
        start.hour = 0; start.minute = 0; start.second = 0
        var end = start; end.hour = 23; end.minute = 59; end.second = 59
        do {
            try DeviceActivityCenter().startMonitoring(retryName(appID),
                during: DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: false),
                events: [event(appID, .retry): DeviceActivityEvent(applications: [token],
                    threshold: DateComponents(minute: minutes), includesPastActivity: false)])
        } catch {
            try? store.update { state in
                state.ledgers[appID.uuidString]?.retryMonitorRegisteredAt = nil
                state.lastMonitorError = "재전화 감지 등록 실패: \(error.localizedDescription)"
            }
            throw error
        }
    }

    static func cancelRetries(_ state: SharedState) {
        DeviceActivityCenter().stopMonitoring(state.apps.map { retryName($0.id) })
    }
}
