import Foundation

/// This reducer runs under a cross-process file lock in both the app and extension.
/// DeviceActivity supplies usage thresholds; this reducer never infers usage from elapsed time.
public enum InterventionPolicy {
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public static func rollDay(_ state: inout SharedState, now: Date, calendar: Calendar = .current) {
        let today = dayKey(now, calendar: calendar)
        guard state.day != today else { return }
        state.day = today
        state.ledgers = [:]
        state.knownApps = state.apps
        if state.preferences.pausedDay != today { state.preferences.pausedDay = nil }
        // Preserve an actual call spanning midnight and its result history.
        state.attempts = Array(state.attempts.suffix(200))
    }

    public static func handleThreshold(_ state: inout SharedState, appID: UUID,
                                       kind: ThresholdKind, now: Date,
                                       approvalGranted: Bool,
                                       calendar: Calendar = .current) -> DetectionDecision {
        rollDay(&state, now: now, calendar: calendar)
        let key = appID.uuidString
        guard state.apps.contains(where: { $0.id == appID }) else { return .skip("removed_app") }
        var ledger = state.ledgers[key] ?? AppDayLedger()
        let decision: DetectionDecision
        if kind == .first && ledger.firstObserved {
            decision = .skip("duplicate_threshold")
        } else if kind == .retry && (ledger.retryArmedAt == nil || ledger.attemptIDs.count != 1) {
            decision = .skip("retry_not_armed")
        } else {
            // A callback can arrive while Family Controls authorization is still
            // settling. Do not permanently consume today's first threshold until
            // the extension can actually use the authorization.
            if kind == .first && state.screenTimeAuthorized { ledger.firstObserved = true }
            if !state.screenTimeAuthorized { decision = .skip("permission_unavailable") }
            else if !state.preferences.proactiveEnabled { decision = .skip("disabled") }
            else if state.preferences.pausedDay == state.day { decision = .skip("paused_today") }
            else if ledger.answered { decision = .skip("already_answered") }
            else if ledger.attemptIDs.count >= 2 { decision = .skip("daily_cap") }
            else if kind == .retry && !state.preferences.retryEnabled { decision = .skip("retry_disabled") }
            else if kind == .retry && !state.attempts.contains(where: {
                $0.id == ledger.attemptIDs.first && [.declined, .unanswered].contains($0.outcome)
            }) { decision = .skip("first_not_missed") }
            else if let active = state.activeCallID,
                    state.busyUntil == nil || state.busyUntil! > now {
                // Consume this checkpoint. No post-call backlog is kept.
                if kind == .retry { ledger.retryArmedAt = nil }
                decision = .skip("busy_\(active.uuidString)")
            } else if !approvalGranted {
                decision = .skip("local_only_apple_approval_pending")
            } else {
                let id = UUID()
                ledger.attemptIDs.append(id)
                if kind == .retry { ledger.retryArmedAt = nil }
                state.attempts.append(CallAttempt(id: id, appID: appID, day: state.day,
                                                 ordinal: ledger.attemptIDs.count, requestedAt: now,
                                                 outcome: .requested))
                state.activeCallID = id
                state.busyUntil = now.addingTimeInterval(60)
                decision = .request(id)
            }
        }
        state.ledgers[key] = ledger
        let label: String
        switch decision { case .request: label = "request_reserved"; case .skip(let reason): label = reason }
        state.detections.append(LocalDetection(id: UUID(), appID: appID, at: now, kind: kind, result: label))
        state.detections = Array(state.detections.suffix(100))
        return decision
    }

    public static func finish(_ state: inout SharedState, callID: UUID, outcome: CallOutcome,
                              now: Date, calendar: Calendar = .current) {
        rollDay(&state, now: now, calendar: calendar)
        guard let i = state.attempts.firstIndex(where: { $0.id == callID }) else {
            if outcome.isTerminal && state.activeCallID == callID {
                state.activeCallID = nil; state.busyUntil = nil
            } else if outcome.wasAnswered {
                state.activeCallID = callID; state.busyUntil = nil
            }
            return
        }
        // Duplicate/late callbacks cannot turn an answered call into a missed one.
        guard !state.attempts[i].outcome.isTerminal else { return }
        if state.attempts[i].answeredAt != nil && [.declined, .unanswered].contains(outcome) { return }
        state.attempts[i].outcome = outcome
        if outcome.wasAnswered { state.attempts[i].answeredAt = state.attempts[i].answeredAt ?? now }
        if outcome.isTerminal { state.attempts[i].finishedAt = now }
        let attempt = state.attempts[i]
        if attempt.day == state.day {
            var ledger = state.ledgers[attempt.appID.uuidString] ?? AppDayLedger()
            if outcome.wasAnswered || attempt.answeredAt != nil { ledger.answered = true; ledger.retryArmedAt = nil }
            if [.declined, .unanswered].contains(outcome), attempt.ordinal == 1,
               state.preferences.retryEnabled, !ledger.answered,
               state.preferences.pausedDay != state.day {
                ledger.retryArmedAt = now
                ledger.retryMinutes = state.preferences.retryMinutes
            }
            state.ledgers[attempt.appID.uuidString] = ledger
        }
        if outcome.isTerminal && state.activeCallID == callID {
            state.activeCallID = nil; state.busyUntil = nil
        } else if outcome.wasAnswered {
            state.activeCallID = callID
            state.busyUntil = nil
        }
    }

    public static func pauseToday(_ state: inout SharedState, now: Date, calendar: Calendar = .current) {
        rollDay(&state, now: now, calendar: calendar)
        state.preferences.pausedDay = state.day
    }
}
