import XCTest
@testable import JiminCore

final class PolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_795_990_000)
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!; return c }
    func fixture() -> SharedState {
        var s = SharedState(); s.screenTimeAuthorized = true
        s.apps = [MonitoredApp(tokenData: Data([1])), MonitoredApp(tokenData: Data([2]), dailyMinutes: 60)]
        InterventionPolicy.rollDay(&s, now: now, calendar: calendar); return s
    }
    func threshold(_ state: inout SharedState, index: Int = 0, kind: ThresholdKind = .first,
                   at: Date? = nil, approved: Bool = true) -> DetectionDecision {
        InterventionPolicy.handleThreshold(&state, appID: state.apps[index].id, kind: kind,
            now: at ?? now, approvalGranted: approved, calendar: calendar)
    }
    func requestID(_ decision: DetectionDecision, file: StaticString = #filePath, line: UInt = #line) -> UUID {
        if case .request(let id) = decision { return id }
        XCTFail("Expected request, got \(decision)", file: file, line: line); return UUID()
    }
    func finish(_ s: inout SharedState, id: UUID, outcome: CallOutcome, at: Date? = nil) {
        InterventionPolicy.finish(&s, callID: id, outcome: outcome, now: at ?? now.addingTimeInterval(30), calendar: calendar)
    }
    func testApprovalPendingRemainsEntirelyLocalAndConsumesNoCallAttempt() {
        var s = fixture()
        XCTAssertEqual(threshold(&s, approved: false), .skip("local_only_apple_approval_pending"))
        XCTAssertEqual(s.attempts.count, 0); XCTAssertNil(s.activeCallID)
        XCTAssertEqual(s.detections.count, 1)
    }
    func testIndependentApplicationsAndNoBacklogDuringActiveCall() {
        var s = fixture(); let id = requestID(threshold(&s))
        XCTAssertEqual(threshold(&s, index: 1), .skip("busy_\(id.uuidString)"))
        finish(&s, id: id, outcome: .ended)
        XCTAssertEqual(threshold(&s, index: 1), .skip("duplicate_threshold"))
        XCTAssertEqual(s.attempts.count, 1)
    }
    func testDeclinedFirstCallArmsOneUsageBasedRetryAndDailyCap() {
        var s = fixture(); let first = requestID(threshold(&s))
        finish(&s, id: first, outcome: .declined)
        let ledger = s.ledgers[s.apps[0].id.uuidString]!
        XCTAssertEqual(ledger.retryMinutes, 20); XCTAssertNotNil(ledger.retryArmedAt)
        let retry = requestID(threshold(&s, kind: .retry, at: now.addingTimeInterval(1230)))
        finish(&s, id: retry, outcome: .unanswered, at: now.addingTimeInterval(1260))
        XCTAssertEqual(s.attempts.count, 2)
        if case .request = threshold(&s, kind: .retry, at: now.addingTimeInterval(2500)) { XCTFail("third call") }
    }
    func testWallClockTimeAloneDoesNotProduceRetry() {
        var s = fixture(); let first = requestID(threshold(&s)); finish(&s, id: first, outcome: .unanswered)
        InterventionPolicy.rollDay(&s, now: now.addingTimeInterval(3600), calendar: calendar)
        XCTAssertEqual(s.attempts.count, 1, "Only an actual additional-usage threshold can call again")
    }
    func testAnsweredAppCannotRetryEvenAfterLateMissedCallback() {
        var s = fixture(); let id = requestID(threshold(&s)); finish(&s, id: id, outcome: .answered)
        finish(&s, id: id, outcome: .unanswered)
        XCTAssertEqual(s.attempts[0].outcome, .answered)
        finish(&s, id: id, outcome: .ended)
        if case .request = threshold(&s, kind: .retry, at: now.addingTimeInterval(2000)) { XCTFail("answered app retried") }
        XCTAssertTrue(s.ledgers[s.apps[0].id.uuidString]!.answered)
    }
    func testNetworkFailureDoesNotCountAsDeclineForRetry() {
        var s = fixture(); let id = requestID(threshold(&s)); finish(&s, id: id, outcome: .failed)
        XCTAssertNil(s.ledgers[s.apps[0].id.uuidString]?.retryArmedAt)
    }
    func testBudgetEditingDoesNotResetAttemptOrThresholdHistory() {
        var s = fixture(); let id = requestID(threshold(&s)); finish(&s, id: id, outcome: .declined)
        s.apps[0].dailyMinutes = 15
        InterventionPolicy.rollDay(&s, now: now.addingTimeInterval(3600), calendar: calendar)
        XCTAssertEqual(threshold(&s), .skip("duplicate_threshold")); XCTAssertEqual(s.attempts.count, 1)
        XCTAssertEqual(s.ledgers[s.apps[0].id.uuidString]?.retryMinutes, 20)
    }
    func testPauseTodayExpiresOnlyOnLocalDateChange() {
        var s = fixture(); InterventionPolicy.pauseToday(&s, now: now, calendar: calendar)
        XCTAssertEqual(threshold(&s), .skip("paused_today"))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let id = requestID(threshold(&s, at: tomorrow)); XCTAssertNotNil(id); XCTAssertNil(s.preferences.pausedDay)
    }
    func testMidnightPreservesAnOngoingCallAndHistory() {
        var s = fixture(); let id = requestID(threshold(&s)); finish(&s, id: id, outcome: .voiceConnected)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        InterventionPolicy.rollDay(&s, now: tomorrow, calendar: calendar)
        XCTAssertEqual(s.activeCallID, id); XCTAssertEqual(s.attempts.count, 1); XCTAssertEqual(s.ledgers.count, 0)
    }
    func testManualCallAlsoBlocksAutomaticEventsForFullCall() {
        var s = fixture(); let manual = UUID(); s.activeCallID = manual; s.busyUntil = now.addingTimeInterval(30)
        finish(&s, id: manual, outcome: .answered)
        XCTAssertNil(s.busyUntil)
        XCTAssertEqual(threshold(&s, at: now.addingTimeInterval(1200)), .skip("busy_\(manual.uuidString)"))
    }
    func testPermissionRevokedAndUserDisabledFailClosed() {
        var s = fixture(); s.screenTimeAuthorized = false
        XCTAssertEqual(threshold(&s), .skip("permission_unavailable"))
        XCTAssertFalse(s.ledgers[s.apps[0].id.uuidString]!.firstObserved)
        s.screenTimeAuthorized = true
        XCTAssertNotNil(requestID(threshold(&s)))
        var t = fixture(); t.preferences.proactiveEnabled = false
        XCTAssertEqual(threshold(&t), .skip("disabled"))
    }
    func testRetryDisabledAndBusyRetryAreNotQueued() {
        var s = fixture(); let first = requestID(threshold(&s)); finish(&s, id: first, outcome: .declined)
        let other = UUID(); s.activeCallID = other; s.busyUntil = nil
        XCTAssertEqual(threshold(&s, kind: .retry, at: now.addingTimeInterval(1300)), .skip("busy_\(other.uuidString)"))
        s.activeCallID = nil
        XCTAssertEqual(threshold(&s, kind: .retry, at: now.addingTimeInterval(1500)), .skip("retry_not_armed"))
    }
    func testFileStoreDoesNotResetCorruptState() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LockedStateStore(directory: dir)
        try store.update { $0.preferences.retryMinutes = 35 }
        XCTAssertEqual(try store.read().preferences.retryMinutes, 35)
        try Data("broken".utf8).write(to: dir.appendingPathComponent("state.json"))
        XCTAssertThrowsError(try store.read())
    }
    func testConcurrentReadModifyWriteDoesNotLoseMemories() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LockedStateStore(directory: dir)
        DispatchQueue.concurrentPerform(iterations: 40) { i in
            try! store.update { $0.preferences.memories.append(ConfirmedMemory(text: "\(i)")) }
        }
        XCTAssertEqual(try store.read().preferences.memories.count, 40)
    }
}

final class ConsentTests: XCTestCase {
    func testNoSaveFromAnOldYesOrYesToDifferentQuestion() {
        let proposal = MemoryProposal(text: "오늘 글을 쓰기로 함", now: Date(timeIntervalSince1970: 100))
        XCTAssertFalse(ConsentGuard.mayConfirmMemory(proposal: proposal, transcript: "응", spokenAt: Date(timeIntervalSince1970: 99), question: .memory, questionAt: Date(timeIntervalSince1970: 101), now: Date(timeIntervalSince1970: 102)))
        XCTAssertFalse(ConsentGuard.mayConfirmMemory(proposal: proposal, transcript: "응", spokenAt: Date(timeIntervalSince1970: 103), question: .accompany, questionAt: Date(timeIntervalSince1970: 101), now: Date(timeIntervalSince1970: 104)))
        XCTAssertTrue(ConsentGuard.mayConfirmMemory(proposal: proposal, transcript: "응, 기억해 줘", spokenAt: Date(timeIntervalSince1970: 103), question: .memory, questionAt: Date(timeIntervalSince1970: 101), now: Date(timeIntervalSince1970: 104)))
    }
    func testAmbiguousSpeechCannotSave() {
        XCTAssertFalse(ConsentGuard.affirmative("응 아니 기억하지 마"))
        XCTAssertFalse(ConsentGuard.affirmative("좋은 것 같기도 하고"))
        XCTAssertFalse(ConsentGuard.affirmative("아니요"))
        XCTAssertEqual(ConsentGuard.classifyQuestion("20분 같이 있을까? 그리고 이걸 기억해도 될까?"), .other)
    }
    func testClearPauseOnlyAndNoNegatedPause() {
        XCTAssertTrue(ConsentGuard.clearlyRequestsPause("오늘은 전화하지 마"))
        XCTAssertTrue(ConsentGuard.clearlyRequestsPause("오늘 연락은 그만해줘"))
        XCTAssertFalse(ConsentGuard.clearlyRequestsPause("오늘 전화 멈추지 마"))
        XCTAssertFalse(ConsentGuard.clearlyRequestsPause("전화 싫은 것 같기도 해"))
    }
    func testLiveFragmentsRequireFreshExplicitAndSettledMemoryConsent() {
        let t = Date(timeIntervalSince1970: 100)
        var tracker = LiveConsentTracker()
        tracker.recordOutput("이걸 기억해도 될까?", startMS: 100, endMS: 900, now: t.addingTimeInterval(1))
        tracker.recordInput("응", startMS: 1_000, endMS: 1_200, now: t.addingTimeInterval(2))
        XCTAssertFalse(tracker.mayConfirmMemory(proposedAt: t, now: t.addingTimeInterval(4)))
        tracker.recordInput(" 기억해 줘", startMS: 1_210, endMS: 1_700, now: t.addingTimeInterval(4))
        tracker.recordOutput(" 알겠어", startMS: 1_710, endMS: 2_000, now: t.addingTimeInterval(4.2))
        XCTAssertFalse(tracker.mayConfirmMemory(proposedAt: t, now: t.addingTimeInterval(4.5)))
        XCTAssertTrue(tracker.mayConfirmMemory(proposedAt: t, now: t.addingTimeInterval(5.3)))
        XCTAssertFalse(tracker.mayConfirmMemory(proposedAt: t.addingTimeInterval(3), now: t.addingTimeInterval(5.3)))
    }
    func testLiveTranscriptRejectsOverlappingAndCorrectedAnswers() {
        let t = Date(timeIntervalSince1970: 100)
        var tracker = LiveConsentTracker()
        tracker.recordOutput("기억해도 될까?", startMS: 1_000, endMS: 2_000, now: t)
        tracker.recordInput("기억해 줘", startMS: 1_700, endMS: 2_100, now: t.addingTimeInterval(1))
        XCTAssertFalse(tracker.mayConfirmMemory(proposedAt: t.addingTimeInterval(-1), now: t.addingTimeInterval(3)))
        tracker.recordInput("응", startMS: 3_000, endMS: 3_200, now: t.addingTimeInterval(4))
        tracker.recordInput(" 아니 기억하지 마", startMS: 3_210, endMS: 4_000, now: t.addingTimeInterval(4.3))
        XCTAssertFalse(tracker.mayConfirmMemory(proposedAt: t.addingTimeInterval(-1), now: t.addingTimeInterval(6)))
    }
    func testLiveCompanionshipAndPauseNeedTheirOwnClearSpeech() {
        let t = Date(timeIntervalSince1970: 100)
        var tracker = LiveConsentTracker()
        tracker.recordOutput("20분 같이 있을까?", startMS: 0, endMS: 900, now: t)
        tracker.recordInput("응", startMS: 1_000, endMS: 1_200, now: t.addingTimeInterval(1))
        XCTAssertTrue(tracker.mayStartTogether(now: t.addingTimeInterval(2.3)))
        XCTAssertFalse(tracker.clearlyRequestsPause(now: t.addingTimeInterval(2.3)))
        tracker.recordInput("오늘 전화 그만해 줘", startMS: 3_000, endMS: 4_000, now: t.addingTimeInterval(4))
        XCTAssertTrue(tracker.clearlyRequestsPause(now: t.addingTimeInterval(5.3)))
    }
}
