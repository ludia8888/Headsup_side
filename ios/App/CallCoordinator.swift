import SwiftUI
import CallKit
import PushKit
import AVFoundation
import WebRTC
import FamilyControls
import JiminCore
import os

// Both delegates are explicitly registered on .main. The imported ObjC protocols
// predate Swift actors; this conformance asserts that queue contract at runtime.
@MainActor final class CallCoordinator: NSObject, ObservableObject, @preconcurrency CXProviderDelegate, @preconcurrency PKPushRegistryDelegate {
    static let shared = CallCoordinator()
    enum Phase: String { case idle, ringing, connecting, talking, together, closing }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var callerName = "지민"
    @Published private(set) var remainingSeconds = 1200
    @Published private(set) var simulatorNotice: String?
    @Published private(set) var muted = false
    @Published var feedbackCallID: UUID?
    weak var model: AppModel?
    var isBusy: Bool { phase != .idle }
    var shouldPresentCallScreen: Bool { isBusy && (simulationFallback || phase != .ringing) }
    private let provider: CXProvider
    private let logger = Logger(subsystem: "com.ludia8888.headsup.jimin", category: "CallKit")
    private let controller = CXCallController()
    private var registry: PKPushRegistry?
    private var pushToken: String?
    private var callID: UUID?
    private var currentProfile: CharacterProfile?
    private var currentOpeningCue: String?
    private var transport: RealtimeTransport?
    private var connectionTask: Task<Void, Never>?
    private var pauseTask: Task<Void, Never>?
    private var resultTask: Task<Void, Error>?
    private var answerAction: CXAnswerCallAction?
    private var ringTimer: Timer?
    private var tickTimer: Timer?
    private var bodyDeadline: Date?
    private var startedAt: Date?
    private var answered = false
    private var simulationFallback = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var consent = LiveConsentTracker()
    private var handledTools = Set<String>()
    private struct LiveTool { let id: String; let name: String; let args: [String: Any] }
    private var pendingTools: [String: [LiveTool]] = [:]

    override private init() {
        let config = CXProviderConfiguration()
        config.supportedHandleTypes = [.generic]; config.supportsVideo = false
        config.maximumCallGroups = 1; config.maximumCallsPerCallGroup = 1
        config.includesCallsInRecents = false
        provider = CXProvider(configuration: config)
        super.init(); provider.setDelegate(self, queue: .main)
        RTCAudioSession.sharedInstance().useManualAudio = true
        RTCAudioSession.sharedInstance().isAudioEnabled = false
    }
    func start() {
        #if !MANUAL_CALL_DEMO
        let registry = PKPushRegistry(queue: .main); registry.delegate = self
        registry.desiredPushTypes = [.voIP]; self.registry = registry
        #endif
    }
    func reconcileInterruptedCall() {
        guard !isBusy, let state = try? SharedResources.store().read(), let id = state.activeCallID,
              (state.busyUntil ?? .distantPast) < Date() else { return }
        try? SharedResources.store().update { state in
            InterventionPolicy.finish(&state, callID: id, outcome: .failed, now: Date())
            if let i = state.callHistory.firstIndex(where: { $0.id == id }) {
                state.callHistory[i].outcome = .failed; state.callHistory[i].finishedAt = Date()
            }
        }
        provider.reportCall(with: id, endedAt: Date(), reason: .failed)
        Task { try? await BackendClient.result(id, .failed) }
        model?.refresh()
    }
    func syncPushToken() async {
        guard let pushToken, (try? SecureConnectionStore.read()) != nil else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        do { _ = try await BackendClient.request("v1/device/push", method: "PUT", body: ["token": pushToken, "environment": environment]) }
        catch { model?.errorMessage = "전화 수신용 기기 등록을 확인하지 못했어요. \(error.localizedDescription)" }
    }
    func manualCall(simulatorPreview: Bool = false) async {
        guard !isBusy, let model else { return }
        guard AVAudioApplication.shared.recordPermission == .granted else {
            await model.requestConversationPermissions()
            guard AVAudioApplication.shared.recordPermission == .granted else { return }
            return await manualCall(simulatorPreview: simulatorPreview)
        }
        model.isWorking = true; defer { model.isWorking = false }
        model.stopPreview()
        #if DEBUG && targetEnvironment(simulator)
        // The Simulator may immediately end a locally reported CallKit call.
        // Keep the real server and GPT-Live path, but present the incoming call in-app.
        let useInAppReception = true
        #else
        let useInAppReception = simulatorPreview
        #endif
        do { try await model.syncNow(); let call = try await BackendClient.manualCall(); receive(call, isVoIP: false, simulatorPreview: useInAppReception) }
        catch { model.errorMessage = error.localizedDescription }
    }
    private func receive(_ envelope: CallEnvelope, isVoIP: Bool, simulatorPreview: Bool = false, completion: @escaping () -> Void = {}) {
        let id = envelope.id
        let update = CXCallUpdate(); update.remoteHandle = CXHandle(type: .generic, value: envelope.displayName)
        update.localizedCallerName = envelope.displayName; update.hasVideo = false
        let duplicate = callID == id
        let otherCall = isBusy && !duplicate
        let localPolicyAllowsPush: Bool
        if isVoIP, let state = try? SharedResources.store().read() {
            localPolicyAllowsPush = SharedResources.automaticDispatchApproved && state.preferences.onboardingComplete &&
                state.preferences.proactiveEnabled && state.preferences.pausedDay != InterventionPolicy.dayKey(Date()) &&
                AuthorizationCenter.shared.authorizationStatus == .approved
        } else { localPolicyAllowsPush = !isVoIP }
        if !duplicate && !otherCall {
            model?.stopPreview()
            callID = id; callerName = envelope.displayName; currentProfile = envelope.character
            currentOpeningCue = envelope.openingCue
            phase = .ringing; answered = false; startedAt = Date(); handledTools = []
            model?.pendingMemory = nil; consent = LiveConsentTracker(); pendingTools = [:]
            simulationFallback = false; simulatorNotice = nil; muted = false
            try? SharedResources.store().update { state in
                if !state.callHistory.contains(where: { $0.id == id }) {
                    var history = LocalCallRecord(id: id, characterName: envelope.displayName, startedAt: Date(), outcome: .ringing)
                    history.arrivalDelaySeconds = max(0, Date().timeIntervalSince(envelope.createdAt))
                    state.callHistory.insert(history, at: 0); state.callHistory = Array(state.callHistory.prefix(100))
                }
                state.activeCallID = id; state.busyUntil = envelope.expiresAt
            }
        }
        #if DEBUG && targetEnvironment(simulator)
        // A deliberately labelled UI inspection path. It uses a real manual server
        // request but does not claim to test system delivery or an AI audio session.
        if simulatorPreview && !isVoIP && !duplicate && !otherCall {
            guard envelope.expiresAt > Date(),
                  !["ended", "failed", "declined", "unanswered"].contains(envelope.status) else {
                finish(.unanswered, reason: .unanswered); completion(); return
            }
            simulationFallback = true
            simulatorNotice = "시뮬레이터 앱 내부 수신 화면\n받으면 실제 AI 음성 연결을 시도해요. 시스템 전화 수신은 iPhone에서 따로 확인해야 해요."
            activateRinging(envelope); completion(); return
        }
        #endif
        // Always report a VoIP push to CallKit immediately, including stale requests.
        provider.reportNewIncomingCall(with: id, update: update) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { completion(); return }
                completion()
                if duplicate { return }
                if otherCall {
                    self.provider.reportCall(with: id, endedAt: Date(), reason: .failed)
                    Task { try? await BackendClient.result(id, .failed) }; return
                }
                if !localPolicyAllowsPush { self.finish(.failed, reason: .failed); return }
                if envelope.expiresAt <= Date() || ["ended", "failed", "declined", "unanswered"].contains(envelope.status) {
                    self.finish(.unanswered, reason: .unanswered); return
                }
                if let error {
                    #if targetEnvironment(simulator)
                    if !isVoIP {
                        self.simulationFallback = true
                        self.simulatorNotice = "시뮬레이터의 앱 내부 수신 화면 · 시스템 전화 수신은 실기기에서 확인해 주세요"
                    } else { self.model?.errorMessage = error.localizedDescription; self.finish(.failed, reason: .failed); return }
                    #elseif MANUAL_CALL_DEMO
                    let failure = error as NSError
                    self.logger.error("Manual incoming call rejected: domain=\(failure.domain, privacy: .public) code=\(failure.code)")
                    self.simulationFallback = true
                    self.simulatorNotice = "아이폰이 시스템 전화 화면을 열지 못했어요. 이 시험 통화는 앱 안에서 계속할게요. 받으면 실제 AI 음성을 연결해요."
                    #else
                    self.model?.errorMessage = "시스템에서 전화 표시를 허용하지 않았어요. 방해금지·서명·전화 설정을 확인해 주세요. \(error.localizedDescription)"
                    self.finish(.failed, reason: .failed); return
                    #endif
                }
                self.activateRinging(envelope)
            }
        }
    }
    private func activateRinging(_ envelope: CallEnvelope) {
        _ = record(.ringing)
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Incoming AI call") { [weak self] in
            Task { @MainActor in self?.finish(.unanswered, reason: .unanswered) }
        }
        ringTimer = Timer.scheduledTimer(withTimeInterval: max(0.1, envelope.expiresAt.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish(.unanswered, reason: .unanswered) }
        }
    }
    func answerFromApp() {
        guard let id = callID, phase == .ringing else { return }
        if simulationFallback {
            try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .defaultToSpeaker])
            try? AVAudioSession.sharedInstance().setActive(true)
            RTCAudioSession.sharedInstance().audioSessionDidActivate(AVAudioSession.sharedInstance())
            RTCAudioSession.sharedInstance().isAudioEnabled = true
            beginAnswer(nil)
        } else { controller.request(CXTransaction(action: CXAnswerCallAction(call: id))) { [weak self] error in
            if let error { Task { @MainActor in self?.model?.errorMessage = error.localizedDescription } }
        } }
    }
    func endFromApp() {
        guard let id = callID else { return }
        if simulationFallback { finish(answered ? .ended : .declined, reason: .remoteEnded) }
        else { controller.request(CXTransaction(action: CXEndCallAction(call: id))) { [weak self] error in
            if let error { Task { @MainActor in self?.model?.errorMessage = error.localizedDescription } }
        } }
    }
    private func beginAnswer(_ action: CXAnswerCallAction?) {
        guard let id = callID, phase == .ringing else { action?.fail(); return }
        guard AVAudioApplication.shared.recordPermission == .granted else {
            action?.fail(); model?.errorMessage = "마이크 권한이 없어 음성을 연결하지 못했어요. 아이폰 설정에서 허용해 주세요."
            finish(.failed, reason: .failed); return
        }
        ringTimer?.invalidate(); ringTimer = nil; endBackgroundTask()
        answered = true; phase = .connecting; answerAction = action
        markCallTime(\.answeredAt)
        connectionTask = Task { [weak self] in
            guard let self else { return }
            var ownedTransport: RealtimeTransport?
            defer {
                if self.callID != id {
                    ownedTransport?.close()
                    if self.transport === ownedTransport { self.transport = nil }
                }
            }
            do {
                // The call lookup and answer receipt are independent network trips.
                // Starting them together avoids making the user wait for both in sequence.
                let answeredOnServer = self.record(.answered)
                async let fetchedCall = BackendClient.call(id)
                let envelope = try await fetchedCall
                guard self.callID == id, !Task.isCancelled else { return }
                self.currentProfile = envelope.character
                self.currentOpeningCue = envelope.openingCue
                try await answeredOnServer.value
                try Task.checkCancellation()
                guard self.callID == id else { throw CancellationError() }
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .defaultToSpeaker])
                let transport = RealtimeTransport(); ownedTransport = transport
                self.transport = transport
                transport.onReady = { [weak self, weak transport] in
                    guard let self, self.callID == id, self.phase == .connecting else { return }
                    self.phase = .talking; self.answerAction?.fulfill(); self.answerAction = nil
                    _ = self.record(.voiceConnected); transport?.greet(cue: self.currentOpeningCue); self.startTicking()
                }
                transport.onFirstRemoteAudioPacket = { [weak self] in self?.markCallTime(\.firstRemoteAudioPacketAt) }
                transport.onFailure = { [weak self] message in self?.model?.errorMessage = message; self?.finish(.failed, reason: .failed) }
                transport.onEvent = { [weak self] event in
                    if event["type"] as? String == "session.closed",
                       let usage = event["usage"] as? [String: Any], let seconds = usage["seconds"] as? Double {
                        Task { try? await BackendClient.liveUsage(id, seconds: seconds) }
                    }
                    self?.handleEvent(event)
                }
                try await transport.connect(callID: id)
                try await Task.sleep(nanoseconds: 12_000_000_000)
                if self.callID == id, self.phase == .connecting { throw BackendClient.APIError("음성 연결이 제시간에 완료되지 않았어요.") }
            } catch is CancellationError {} catch {
                guard self.callID == id else { return }
                self.model?.errorMessage = error.localizedDescription; self.answerAction?.fail(); self.answerAction = nil
                self.finish(.failed, reason: .failed)
            }
        }
    }
    func beginTogether(fromButton: Bool = true) {
        guard phase == .talking else { return }
        if !fromButton && !consent.mayStartTogether(now: Date()) { return }
        bodyDeadline = Date().addingTimeInterval(20 * 60); remainingSeconds = 1200
        phase = .together; transport?.accompany()
    }
    func setMuted(_ muted: Bool) { self.muted = muted; transport?.setMuted(muted) }
    private func startTicking() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    func tick() {
        if let start = startedAt, Date().timeIntervalSince(start) > 29 * 60, phase != .closing { closeWithGoodbye(); return }
        if phase == .together, let deadline = bodyDeadline {
            remainingSeconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
            if remainingSeconds == 0 { closeWithGoodbye() }
        }
    }
    private func closeWithGoodbye() {
        guard phase == .talking || phase == .together else { return }
        phase = .closing; transport?.goodbye()
        let endingID = callID
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.phase == .closing, self.callID == endingID else { return }
            self.finish(.ended, reason: .remoteEnded)
        }
    }
    private func handleEvent(_ event: [String: Any]) {
        guard let type = event["type"] as? String else { return }
        if type == "session.input_transcript.delta", let delta = event["delta"] as? String,
           let start = event["start_ms"] as? Int, let end = event["end_ms"] as? Int {
            if !delta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let id = callID,
               let record = try? SharedResources.store().read().callHistory.first(where: { $0.id == id }),
               record.firstOutputTranscriptAt != nil {
                markCallTime(\.firstUserReplyAt)
            }
            consent.recordInput(delta, startMS: start, endMS: end, now: Date())
            pauseTask?.cancel()
            let id = callID
            pauseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1_300))
                guard !Task.isCancelled, let self, self.callID == id else { return }
                if self.consent.clearlyRequestsPause(now: Date()) { self.model?.pauseToday() }
            }
        } else if type == "session.output_transcript.delta", let delta = event["delta"] as? String,
                  let start = event["start_ms"] as? Int, let end = event["end_ms"] as? Int {
            if !delta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { markCallTime(\.firstOutputTranscriptAt) }
            consent.recordOutput(delta, startMS: start, endMS: end, now: Date())
        } else if type == "response.event", let inner = event["event"] as? [String: Any],
                  let innerType = inner["type"] as? String {
            let key = event["delegation_id"] as? String ?? "single-response"
            if innerType == "response.output_item.done", let item = inner["item"] as? [String: Any],
               item["type"] as? String == "function_call", let toolID = item["call_id"] as? String,
               let name = item["name"] as? String, handledTools.insert(toolID).inserted {
                let raw = item["arguments"] as? String ?? "{}"
                let args = raw.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                pendingTools[key, default: []].append(LiveTool(id: toolID, name: name, args: args))
            } else if innerType == "response.completed", let calls = pendingTools.removeValue(forKey: key), !calls.isEmpty {
                let id = callID
                Task { [weak self] in
                    guard let self else { return }
                    for call in calls {
                        // Live transcript fragments have no completion signal. Give late
                        // corrections time to arrive before evaluating a consent action.
                        if ["confirm_memory", "start_body_doubling", "pause_today"].contains(call.name) {
                            try? await Task.sleep(for: .milliseconds(1_300))
                        }
                        guard self.callID == id else { return }
                        self.transport?.functionResult(callID: call.id, result: self.handleTool(call.name, args: call.args))
                    }
                    if self.callID == id { self.transport?.continueBackend() }
                }
            } else if innerType == "response.failed" {
                model?.errorMessage = "AI 대화 작업이 완료되지 않았어요. 다시 말씀해 주세요."
            }
        } else if type == "session.closed" {
            if callID != nil {
                let reason = event["reason"] as? String
                finish(phase == .closing || reason == "remote_hangup" || reason == "close_requested" ? .ended : .failed,
                       reason: .remoteEnded)
            }
        } else if type == "error" {
            model?.errorMessage = "AI 음성 응답에 문제가 생겼어요. 통화를 다시 시험해 주세요."
        }
    }
    private func handleTool(_ name: String, args: [String: Any]) -> [String: Any] {
        var result: [String: Any] = ["ok": false, "reason": "explicit_confirmation_required"]
        switch name {
        case "propose_memory":
            if let text = args["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 500 {
                let proposal = MemoryProposal(text: text); model?.pendingMemory = proposal
                consent = LiveConsentTracker()
                result = ["ok": true, "saved": false, "proposal_id": proposal.id.uuidString,
                          "next": "사용자에게 정확히 이 내용을 기억해도 되는지 확인하세요."]
            }
        case "confirm_memory":
            if let proposal = model?.pendingMemory, args["proposal_id"] as? String == proposal.id.uuidString,
               consent.mayConfirmMemory(proposedAt: proposal.proposedAt, now: Date()) {
                model?.confirmMemory(proposal)
                result = ["ok": model?.pendingMemory == nil, "saved": model?.pendingMemory == nil]
                consent = LiveConsentTracker()
            }
        case "start_body_doubling":
            beginTogether(fromButton: false); result = ["ok": phase == .together, "minutes": 20]
        case "pause_today":
            if consent.clearlyRequestsPause(now: Date()) {
                model?.pauseToday(); result = ["ok": true, "paused_today": true]
            }
        default: result = ["ok": false, "reason": "unknown_tool"]
        }
        return result
    }
    private func markCallTime(_ field: WritableKeyPath<LocalCallRecord, Date?>) {
        guard let id = callID else { return }
        do {
            let changed = try SharedResources.store().update { state -> Bool in
                guard let index = state.callHistory.firstIndex(where: { $0.id == id }),
                      state.callHistory[index][keyPath: field] == nil else { return false }
                state.callHistory[index][keyPath: field] = Date()
                return true
            }
            if changed { model?.refresh() }
        } catch { model?.errorMessage = "통화 지연 기록을 저장하지 못했어요. \(error.localizedDescription)" }
    }
    @discardableResult private func record(_ outcome: CallOutcome) -> Task<Void, Error> {
        let id = callID
        if let id {
            try? SharedResources.store().update { state in
                InterventionPolicy.finish(&state, callID: id, outcome: outcome, now: Date())
                if let i = state.callHistory.firstIndex(where: { $0.id == id }) {
                    state.callHistory[i].outcome = outcome
                    if outcome == .voiceConnected { state.callHistory[i].voiceConnectedAt = Date() }
                    if outcome.isTerminal { state.callHistory[i].finishedAt = Date() }
                }
            }
            model?.refresh()
        }
        let previous = resultTask
        let task = Task { if let previous { try? await previous.value }; if let id { try await BackendClient.result(id, outcome) } }
        resultTask = task; return task
    }
    private func finish(_ outcome: CallOutcome, reason: CXCallEndedReason) {
        guard let id = callID else { return }
        let appID = (try? SharedResources.store().read())?.attempts.first(where: { $0.id == id })?.appID
        _ = record(outcome)
        answerAction?.fail(); answerAction = nil
        connectionTask?.cancel(); connectionTask = nil
        pauseTask?.cancel(); pauseTask = nil
        ringTimer?.invalidate(); tickTimer?.invalidate(); ringTimer = nil; tickTimer = nil
        transport?.close(); transport = nil; endBackgroundTask()
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        if !simulationFallback { provider.reportCall(with: id, endedAt: Date(), reason: reason) }
        if answered { feedbackCallID = id }
        callID = nil; currentOpeningCue = nil; phase = .idle; bodyDeadline = nil; startedAt = nil
        model?.pendingMemory = nil
        if let appID, [.declined, .unanswered].contains(outcome) {
            do { try ScreenTimeScheduler.armMissedCallRetry(appID: appID) }
            catch { model?.errorMessage = error.localizedDescription }
        }
    }
    private func endBackgroundTask() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
    func providerDidReset(_ provider: CXProvider) {
        if !simulationFallback { finish(.failed, reason: .failed) }
    }
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) { beginAnswer(action) }
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        guard callID == action.callUUID else { action.fulfill(); return }
        finish(answered ? .ended : .declined, reason: .remoteEnded); action.fulfill()
    }
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) { setMuted(action.isMuted); action.fulfill() }
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) { action.fail(); finish(.failed, reason: .failed) }
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession); RTCAudioSession.sharedInstance().isAudioEnabled = true
    }
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession); RTCAudioSession.sharedInstance().isAudioEnabled = false
    }
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        pushToken = pushCredentials.token.map { String(format: "%02x", $0) }.joined(); Task { await syncPushToken() }
    }
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        pushToken = nil; Task { _ = try? await BackendClient.request("v1/device/push", method: "DELETE") }
    }
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        let call = payload.dictionaryPayload["call"] as? [String: Any]
        let id = (call?["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = (call?["createdAt"] as? String).flatMap { formatter.date(from: $0) } ?? Date.distantPast
        let expiresAt = (call?["expiresAt"] as? String).flatMap { formatter.date(from: $0) } ?? Date.distantPast
        let envelope = CallEnvelope(id: id, displayName: call?["displayName"] as? String ?? "AI 전화",
            createdAt: createdAt, expiresAt: expiresAt, status: "requested", delivery: "push", character: nil,
            openingCue: nil, instructions: nil)
        receive(envelope, isVoIP: true, completion: completion)
    }
}
