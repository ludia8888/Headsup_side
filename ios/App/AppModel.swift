import SwiftUI
import FamilyControls
import DeviceActivity
import AVFoundation
import UserNotifications
import JiminCore

@MainActor final class AppModel: ObservableObject {
    enum ConnectionReadiness {
        case notConnected, needsKey, ready, unavailable
        var label: String {
            switch self { case .notConnected: "설정 필요"; case .needsKey: "준비 필요"; case .ready: "연결됨"; case .unavailable: "확인 필요" }
        }
    }
    @Published private(set) var state = SharedState()
    @Published var selection = FamilyActivitySelection()
    @Published var errorMessage: String?
    @Published var pendingMemory: MemoryProposal?
    @Published var backendConnected = false
    @Published private(set) var connectionReadiness = ConnectionReadiness.notConnected
    @Published private(set) var checkingConnection = false
    @Published var isWorking = false
    @Published var sampleStatus: String?
    private var player: AVAudioPlayer?
    private var previewRevision = 0
    private let localSpeech = AVSpeechSynthesizer()
    private var syncTask: Task<Void, Never>?
    private var profileRevision = 0
    var calls: CallCoordinator { .shared }

    init() {
        refresh()
        backendConnected = (try? SecureConnectionStore.read()) != nil
        calls.model = self
        calls.reconcileInterruptedCall()
    }
    func refresh() {
        do {
            state = try SharedResources.store().update { state in
                InterventionPolicy.rollDay(&state, now: Date())
                state.screenTimeAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
                return state
            }
            selection = FamilyActivitySelection()
            selection.applicationTokens = Set(state.apps.compactMap(ScreenTimeScheduler.token))
            if !state.screenTimeAuthorized { DeviceActivityCenter().stopMonitoring() }
        } catch { errorMessage = error.localizedDescription }
    }
    func change(_ update: (inout SharedState) -> Void, schedule: Bool = false, sync: Bool = true) {
        do {
            state = try SharedResources.store().update { state in
                InterventionPolicy.rollDay(&state, now: Date()); update(&state); return state
            }
            if schedule && state.preferences.onboardingComplete { try ScreenTimeScheduler.replaceFirstThresholds(state) }
            if sync { syncProfileSoon() }
        } catch { errorMessage = error.localizedDescription }
    }
    func updateCharacter(_ update: (inout CharacterProfile) -> Void) { change { update(&$0.preferences.profile) } }
    func setBudget(_ id: UUID, minutes: Int) {
        change({ state in if let i = state.apps.firstIndex(where: { $0.id == id }) {
            state.apps[i].dailyMinutes = min(1440, max(1, minutes))
            if let j = state.knownApps.firstIndex(where: { $0.id == id }) { state.knownApps[j] = state.apps[i] }
        } }, schedule: true, sync: false)
    }
    func applySelection() {
        guard selection.applicationTokens.count <= 10 else {
            errorMessage = "첫 시험에서는 앱을 최대 10개까지 골라 주세요."; refresh(); return
        }
        // Only explicit application tokens are tracked, never the entire category.
        guard selection.categoryTokens.isEmpty, selection.webDomainTokens.isEmpty else {
            errorMessage = "앱별 한도를 위해 카테고리나 웹사이트 대신 개별 앱을 선택해 주세요."; refresh(); return
        }
        let tokens = selection.applicationTokens
        let removed = state.apps.filter { app in !tokens.contains(where: { $0 == ScreenTimeScheduler.token(app) }) }
        DeviceActivityCenter().stopMonitoring(removed.map { ScreenTimeScheduler.retryName($0.id) })
        change({ state in
            let known = state.apps + state.knownApps
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            state.apps = tokens.compactMap { token in
                known.first(where: { ScreenTimeScheduler.token($0) == token }) ??
                    (try? MonitoredApp(tokenData: encoder.encode(token)))
            }.sorted { $0.id.uuidString < $1.id.uuidString }
            for app in state.apps where !state.knownApps.contains(where: { $0.id == app.id }) { state.knownApps.append(app) }
        }, schedule: true, sync: false)
    }
    func authorizeScreenTime() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refresh(); return state.screenTimeAuthorized
        } catch { errorMessage = "사용 시간 권한을 허용하지 않아도 수동 통화는 시험할 수 있어요. \(error.localizedDescription)"; return false }
    }
    func requestConversationPermissions() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        if !granted { errorMessage = "마이크 권한이 있어야 통화할 수 있어요. 아이폰 설정에서 허용해 주세요." }
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        catch { errorMessage = error.localizedDescription }
    }
    func pauseToday() {
        change { InterventionPolicy.pauseToday(&$0, now: Date()) }
        ScreenTimeScheduler.cancelRetries(state)
    }
    func setProactive(_ enabled: Bool) {
        change { $0.preferences.proactiveEnabled = enabled }
        // Keep the already-started additional-usage counter. The policy still drops
        // an event reached while this switch is off; switching on cannot reset usage.
    }
    func setRetry(_ enabled: Bool) {
        change { state in
            state.preferences.retryEnabled = enabled
            if !enabled {
                for key in state.ledgers.keys { state.ledgers[key]?.retryArmedAt = nil }
            }
        }
        if !enabled { ScreenTimeScheduler.cancelRetries(state) }
    }
    func confirmMemory(_ proposal: MemoryProposal) {
        guard pendingMemory?.id == proposal.id else { return }
        guard state.preferences.memories.count < 100 else { errorMessage = "기억은 100개까지 저장할 수 있어요. 먼저 필요 없는 기억을 지워 주세요."; return }
        change { $0.preferences.memories.append(ConfirmedMemory(text: proposal.text)) }
        pendingMemory = nil
    }
    func saveEditedMemory(_ id: UUID, text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 500 else { return }
        change { state in if let i = state.preferences.memories.firstIndex(where: { $0.id == id }) {
            state.preferences.memories[i].text = value; state.preferences.memories[i].confirmedAt = Date()
        } }
    }
    func deleteMemory(_ id: UUID) { change { $0.preferences.memories.removeAll { $0.id == id } } }
    func connect(url: String, code: String) async {
        guard let base = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)), let host = base.host,
              base.scheme == "https" || (base.scheme == "http" && (host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local"))),
              base.user == nil, base.password == nil, base.query == nil else {
            errorMessage = "HTTPS 서버 주소를 입력해 주세요. 시뮬레이터에서는 http://127.0.0.1:8787을 사용할 수 있어요."; return
        }
        isWorking = true; defer { isWorking = false }
        errorMessage = nil
        do {
            let connection = try await BackendClient.register(baseURL: base, pairingCode: code)
            try SecureConnectionStore.save(connection); backendConnected = true
            try await BackendClient.sync(state.preferences)
            await calls.syncPushToken()
            await checkConnection()
        } catch { errorMessage = error.localizedDescription }
    }
    func checkConnection() async {
        guard backendConnected else { connectionReadiness = .notConnected; return }
        guard !checkingConnection else { return }
        checkingConnection = true; defer { checkingConnection = false }
        do {
            let health = try await BackendClient.health()
            guard backendConnected else { connectionReadiness = .notConnected; return }
            connectionReadiness = health.ok && health.voiceConfigured ? .ready : .needsKey
        } catch { connectionReadiness = backendConnected ? .unavailable : .notConnected }
    }
    func connectLocalSimulator(_ url: URL) {
        #if targetEnvironment(simulator)
        guard url.scheme == "jimin-local", url.host == "connect", !calls.isBusy, !isWorking,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = parts.queryItems?.first(where: { $0.name == "code" })?.value,
              code.count >= 16, code.count <= 100,
              code.allSatisfy({ $0.isLetter || $0.isNumber }) else { return }
        // This bootstrap is deliberately limited to the Mac's loopback server and simulator.
        // It never accepts an arbitrary server URL or an OpenAI API key.
        guard !backendConnected else { return }
        Task { await connect(url: "http://127.0.0.1:8787", code: code) }
        #endif
    }
    func disconnectAndDelete() async {
        guard !calls.isBusy else { errorMessage = "통화를 끝낸 뒤 서버 연결을 삭제해 주세요."; return }
        do {
            _ = try await BackendClient.request("v1/device", method: "DELETE")
            SecureConnectionStore.remove(); backendConnected = false; connectionReadiness = .notConnected
        } catch { errorMessage = "서버에서 삭제를 확인하지 못했어요. 연결 정보는 유지했어요. \(error.localizedDescription)" }
    }
    func syncNow() async throws { await syncTask?.value; try await BackendClient.sync(state.preferences) }
    private func syncProfileSoon() {
        guard backendConnected else { return }
        profileRevision += 1
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                try? await Task.sleep(nanoseconds: 350_000_000)
                let revision = self.profileRevision
                // Send only complete names; editing an empty text field is local.
                if !self.state.preferences.profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !self.state.preferences.profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    do { try await BackendClient.sync(self.state.preferences) }
                    catch { self.errorMessage = "새 설정은 기기에 저장했지만 서버 반영은 아직 확인하지 못했어요. \(error.localizedDescription)" }
                }
                if revision == self.profileRevision { break }
            } while true
            self.syncTask = nil
        }
    }
    func playSample(_ persona: Persona, profile: CharacterProfile? = nil) async {
        guard !calls.isBusy else { return }
        previewRevision += 1
        let revision = previewRevision
        localSpeech.stopSpeaking(at: .immediate); player?.stop()
        var prefs = state.preferences; prefs.profile = profile ?? prefs.profile; prefs.profile.persona = persona; prefs.memories = []
        if backendConnected && connectionReadiness == .ready {
            sampleStatus = "AI 음성 예시를 준비하는 중"
            do {
                let data = try await BackendClient.request("v1/voice-preview", body: BackendClient.profileBody(prefs))
                guard !calls.isBusy, previewRevision == revision else { return }
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                player = try AVAudioPlayer(data: data); player?.play()
                sampleStatus = "AI가 만든 음성 예시 · 실제 통화는 Realtime 음성이에요"
            } catch { if previewRevision == revision { errorMessage = error.localizedDescription; sampleStatus = nil } }
        } else {
            // This preview is deliberately labeled, never passed off as the selected AI voice.
            sampleStatus = "아이폰 기본 음성으로 말투 미리 듣기 · AI 목소리는 서버 연결 후"
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            let utterance = AVSpeechUtterance(string: persona.sample.replacingOccurrences(of: "자기야", with: prefs.profile.nickname))
            utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR"); utterance.rate = 0.46
            localSpeech.speak(utterance)
        }
    }
    func stopPreview() { previewRevision += 1; player?.stop(); localSpeech.stopSpeaking(at: .immediate); sampleStatus = nil }
}
