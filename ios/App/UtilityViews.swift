import SwiftUI
import JiminCore

struct ConnectionView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var calls = CallCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @State private var url = "http://127.0.0.1:8787"
    @State private var code = ""
    @State private var advanced = false
    @State private var deleting = false
    @State private var pushTestScheduled = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 16) {
                        CharacterAvatar(size: 68)
                        SectionHeading(title: "목소리로 만날 준비", detail: "처음 한 번만 연결하면 돼요.")
                    }
                    connectionStatus
                    #if DEBUG && targetEnvironment(simulator)
                    if model.backendConnected {
                        Button {
                            model.errorMessage = nil
                            dismiss()
                            Task { await model.calls.manualCall(simulatorPreview: true) }
                        } label: {
                            Label("시뮬레이터 전화 받기 시험", systemImage: "phone.badge.waveform")
                                .font(.subheadline).frame(minHeight: 44)
                        }.disabled(model.isWorking || model.calls.isBusy)
                        Text("앱 안에 수신 화면을 띄워요. 받기를 누르면 실제 AI 음성 연결을 시도해요. 시스템 수신 화면은 iPhone에서 따로 시험해야 해요.")
                            .font(.caption).foregroundStyle(Palette.muted).lineSpacing(3)
                    }
                    #endif
                    #if DEBUG && !targetEnvironment(simulator)
                    if model.backendConnected {
                        pushRegistrationStatus
                    }
                    SecondaryButton(title: "잠금 화면 전화 시험", icon: "iphone.radiowaves.left.and.right") {
                        if !model.backendConnected { advanced = true }
                        else { Task { if await model.calls.requestPushTest() { pushTestScheduled = true } } }
                    }.disabled(model.isWorking || model.calls.isBusy ||
                               (model.backendConnected && calls.pushRegistrationPhase != .registered))
                    Text(model.backendConnected
                         ? "누르면 약 8초 뒤 실제 인터넷 전화가 와요. 앱 사용 시간은 전송하지 않아요. 잠금 화면을 보려면 안내가 뜬 뒤 iPhone을 잠가 주세요."
                         : "먼저 아래 ‘시험 서버 연결하기’에서 이 지민 앱을 연결해 주세요. 이전 ‘지민 통화 시험’ 앱의 연결은 자동으로 옮겨지지 않아요.")
                        .font(.caption).foregroundStyle(Palette.muted).lineSpacing(3)
                    #endif
                    if model.backendConnected {
                        SecondaryButton(title: model.checkingConnection ? "연결 확인 중" : "연결 다시 확인", icon: "arrow.clockwise") {
                            Task { await model.checkConnection() }
                        }.disabled(model.checkingConnection)
                    }
                    DisclosureGroup(model.backendConnected ? "시험 연결 설정 보기" : "시험 서버 연결하기", isExpanded: $advanced) {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("서버 주소").font(.caption).foregroundStyle(Palette.muted)
                                TextField("https://…", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text("연결 코드").font(.caption).foregroundStyle(Palette.muted)
                                SecureField("서버에서 받은 연결 코드", text: $code).textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                            }
                            PrimaryButton(title: model.isWorking ? "연결하는 중" : "이 기기에 연결", icon: "link", disabled: model.isWorking || code.isEmpty, loading: model.isWorking) {
                                Task { await model.connect(url: url, code: code); if model.backendConnected && model.errorMessage == nil { code = ""; advanced = false } }
                            }
                            Text("시뮬레이터는 이 Mac의 localhost 주소를 사용해요. 실제 아이폰에는 HTTPS 서버 주소가 필요해요. OpenAI API 키는 앱에 입력하지 않아요.")
                                .font(.caption).foregroundStyle(Palette.muted).lineSpacing(4)
                        }.padding(.top, 18)
                    }.font(.subheadline.weight(.semibold))
                    if let error = model.errorMessage {
                        InlineNotice(title: "연결을 마치지 못했어요.", detail: error, icon: "exclamationmark.circle", warning: true)
                    }
                    if model.backendConnected {
                        Button("서버의 내 정보와 연결 삭제", role: .destructive) { deleting = true }
                            .font(.subheadline).frame(minHeight: 44).foregroundStyle(Palette.danger)
                    }
                    Label("연결 정보는 이 기기의 안전한 저장소에 보관해요.", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(Palette.muted).lineSpacing(3)
                }.padding(24)
            }.background(Palette.paper).navigationTitle("통화 연결").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { model.errorMessage = nil; dismiss() } } }
                .task {
                    advanced = !model.backendConnected
                    await model.checkConnection()
                    if model.backendConnected { await calls.syncPushToken() }
                }
                .confirmationDialog("서버의 내 정보와 연결을 삭제할까요?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("서버 정보와 연결 삭제", role: .destructive) { Task { await model.disconnectAndDelete(); if !model.backendConnected { dismiss() } } }
                    Button("취소", role: .cancel) {}
                } message: { Text("서버의 기기 등록, 캐릭터 설정, 기억과 통화 기록이 삭제돼요. 이 기기에 저장한 기억은 ‘우리’에 남아 있어요.") }
                .alert("전화 시험을 예약했어요", isPresented: $pushTestScheduled) {
                    Button("확인") {}
                } message: {
                    Text("약 8초 안에 iPhone을 잠가 주세요. 잠금 화면에 지민 전화가 오면 받아서 실제 AI 음성을 확인할 수 있어요.")
                }
        }
    }
    #if DEBUG && !targetEnvironment(simulator)
    @ViewBuilder private var pushRegistrationStatus: some View {
        switch calls.pushRegistrationPhase {
        case .registered:
            InlineNotice(title: "iPhone 전화 수신 등록 완료", detail: "이 기기로 시험 전화를 보낼 준비가 됐어요.", icon: "checkmark.circle")
        case .waitingForToken, .starting:
            InlineNotice(title: "iPhone 전화 수신 등록을 기다리는 중", detail: "iOS에서 전화 수신용 번호를 아직 받지 못했어요. 인터넷을 확인하고 앱을 잠시 열어 두세요.", icon: "iphone.radiowaves.left.and.right", warning: true)
        case .needsConnection:
            InlineNotice(title: "전화 수신 등록에 서버 연결이 필요해요", detail: "아래에서 이 iPhone을 시험 서버에 연결해 주세요.", icon: "link", warning: true)
        case .registering:
            InlineNotice(title: "iPhone 전화 수신 등록 중", detail: "iOS에서 받은 수신 정보를 시험 서버에 확인하고 있어요.", icon: "arrow.triangle.2.circlepath")
        case .failed:
            InlineNotice(title: "iPhone 전화 수신 등록 실패", detail: "서버 연결과 인터넷을 확인한 뒤 아래 버튼으로 다시 시도해 주세요.", icon: "exclamationmark.circle", warning: true)
            SecondaryButton(title: "전화 수신 등록 다시 시도", icon: "arrow.clockwise") {
                Task { await calls.syncPushToken() }
            }
        }
    }
    #endif
    @ViewBuilder private var connectionStatus: some View {
        switch model.connectionReadiness {
        case .ready:
            InlineNotice(title: "통화 연결을 준비했어요.", detail: "홈의 ‘대화하기’에서 실제 음성 연결을 시작해요.", icon: "checkmark.circle")
        case .notConnected:
            InlineNotice(title: "연결 코드가 필요해요.", detail: "시험 서버에서 받은 주소와 연결 코드를 아래에 입력해 주세요.", icon: "link")
        case .needsKey:
            InlineNotice(title: "기기는 연결됐어요. 음성 설정이 남았어요.", detail: "이 Mac의 비공개 설정 화면에서 서버의 OpenAI API 키를 입력한 뒤 연결을 다시 확인해 주세요.", icon: "waveform", warning: true)
            #if targetEnvironment(simulator)
            Link(destination: URL(string: "http://127.0.0.1:8788")!) {
                Label("Mac의 비공개 키 설정 열기", systemImage: "arrow.up.right.square").font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
            #endif
        case .unavailable:
            InlineNotice(title: "지금 연결을 확인하지 못했어요.", detail: "인터넷과 시험 서버 실행 상태를 확인하고 다시 눌러 주세요.", icon: "wifi.exclamationmark", warning: true)
        }
    }
}

struct ActiveCallView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var calls = CallCoordinator.shared
    var body: some View {
        ZStack {
            CharacterScene(dimmed: true).ignoresSafeArea()
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 13) {
                            Label("AI 음성 통화", systemImage: "waveform").font(.caption.weight(.medium)).foregroundStyle(Palette.ink.opacity(0.8))
                            Text(calls.callerName).font(.largeTitle.weight(.bold)).foregroundStyle(Palette.ink)
                                .multilineTextAlignment(.center).lineLimit(3)
                            HStack(spacing: 9) {
                                if calls.phase == .connecting { ProgressView().tint(Palette.ink) }
                                Text(status).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.85))
                            }
                        }.frame(maxWidth: .infinity).padding(.top, 24)
                        Spacer(minLength: 220)
                        VStack(spacing: 20) {
                            if calls.phase == .together { togetherTime }
                            if calls.phase == .talking {
                                SecondaryButton(title: "20분 조용히 같이 있기", icon: "heart") { calls.beginTogether() }
                            }
                            if let proposal = model.pendingMemory {
                                Surface {
                                    VStack(alignment: .leading, spacing: 14) {
                                        Label("이렇게 기억해도 될까?", systemImage: "book.closed").font(.headline)
                                        Text(proposal.text).font(.body).lineSpacing(4)
                                        PrimaryButton(title: "확인하고 기억해 줘", icon: "checkmark") { model.confirmMemory(proposal) }
                                        Button("저장하지 마") { model.pendingMemory = nil }.font(.subheadline).frame(maxWidth: .infinity).frame(minHeight: 44)
                                    }.foregroundStyle(Palette.ink)
                                }
                            }
                            if let notice = calls.simulatorNotice {
                                Text(notice).font(.caption).foregroundStyle(Palette.muted)
                                    .multilineTextAlignment(.center).lineSpacing(3)
                            }
                        }.padding(.top, 24).padding(.bottom, 20)
                    }
                    .padding(.horizontal, 28).frame(minHeight: geometry.size.height)
                }.scrollIndicators(.hidden)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .interactiveDismissDisabled()
        .alert("음성 연결 확인", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("확인", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
    private var togetherTime: some View {
        VStack(spacing: 12) {
            Text(String(format: "%02d:%02d", calls.remainingSeconds / 60, calls.remainingSeconds % 60))
                .font(.system(.largeTitle, design: .rounded).weight(.medium)).monospacedDigit().foregroundStyle(Palette.ink)
            ProgressView(value: Double(calls.remainingSeconds), total: 1200).tint(Palette.rose).frame(maxWidth: 160)
                .accessibilityLabel("함께하는 시간 \(calls.remainingSeconds / 60)분 남음")
            Text("조용히 같이 있을게.\n말하고 싶으면 언제든 말해.").font(.subheadline)
                .foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(5)
        }
    }
    private var controls: some View {
        VStack(spacing: 18) {
            HStack(spacing: 44) {
                if calls.phase == .ringing {
                    callButton("거절", icon: "phone.down.fill", color: Palette.danger, foreground: Palette.paper) { calls.endFromApp() }
                    callButton("받기", icon: "phone.fill", color: Palette.sage, foreground: Palette.paper) { calls.answerFromApp() }
                } else {
                    callButton(calls.muted ? "음소거 해제" : "음소거", icon: calls.muted ? "mic.slash.fill" : "mic.fill",
                               color: calls.muted ? Palette.rose : Palette.surface, foreground: calls.muted ? Palette.paper : Palette.ink) { calls.setMuted(!calls.muted) }
                    callButton("끊기", icon: "phone.down.fill", color: Palette.danger, foreground: Palette.paper) { calls.endFromApp() }
                }
            }
            Button(model.state.preferences.pausedDay == model.state.day ? "오늘 자동 연락은 쉬는 중" : "오늘은 더 연락하지 마") { model.pauseToday() }
                .font(.caption).foregroundStyle(Palette.muted).frame(minHeight: 44).disabled(model.state.preferences.pausedDay == model.state.day)
        }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 8).frame(maxWidth: .infinity).background(Palette.callBackground)
    }
    private var status: String {
        switch calls.phase {
        case .idle: "통화 종료"
        case .ringing: "전화가 왔어요"
        case .connecting: "목소리를 연결하고 있어요"
        case .talking: "한마디만 답하고 끊어도 좋아"
        case .together: "지금, 같이 있는 중"
        case .closing: "마지막 인사를 나누고 있어요"
        }
    }
    private func callButton(_ title: String, icon: String, color: Color, foreground: Color = Palette.ink, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 25, weight: .medium)).foregroundStyle(foreground)
                    .frame(width: 68, height: 68).background(color, in: Circle())
                Text(title).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.8))
            }.frame(minWidth: 90)
        }.buttonStyle(PressStyle()).accessibilityLabel(title)
    }
}

struct FeedbackView: View {
    let callID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var firstLine = "unknown"
    @State private var stopped = "unknown"
    @State private var tomorrow = "unknown"
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ScreenHeading(title: "전화는 어땠어요?", subtitle: "네가 느낀 그대로 알려줘요.")
                    question("첫마디가 답하고 싶어졌나요?", value: $firstLine, choices: [("yes", "바로 답하고 싶었어요"), ("no", "별로 끌리지 않았어요"), ("unknown", "기억나지 않아요")])
                    question("보던 앱을 멈췄나요?", value: $stopped, choices: [("yes", "멈췄어요"), ("no", "계속 봤어요"), ("unknown", "말하지 않을래요")])
                    question("내일도 전화받고 싶나요?", value: $tomorrow, choices: [("yes", "받고 싶어요"), ("no", "쉬고 싶어요"), ("unknown", "아직 모르겠어요")])
                    if let error { InlineNotice(title: "답을 저장하지 못했어요.", detail: error, warning: true) }
                    Text("답은 네가 알려준 경험으로 기록해요. 전화 수신만으로 앱을 멈췄다고 판단하지 않아요.").font(.caption).foregroundStyle(Palette.muted).lineSpacing(4)
                }.padding(24)
            }.background(Palette.paper).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("건너뛰기") { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    PrimaryButton(title: saving ? "저장 중" : "알려주기", icon: "checkmark", disabled: saving, loading: saving) { Task { await save() } }
                        .padding(24).background(Palette.paper)
                }
        }.presentationDetents([.large])
    }
    private func question(_ title: String, value: Binding<String>, choices: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ForEach(choices, id: \.0) { choice in
                Button { value.wrappedValue = choice.0 } label: {
                    HStack {
                        Text(choice.1).font(.body)
                        Spacer()
                        Image(systemName: value.wrappedValue == choice.0 ? "checkmark.circle.fill" : "circle")
                    }.foregroundStyle(value.wrappedValue == choice.0 ? Palette.rose : Palette.muted)
                        .padding(16).frame(minHeight: 52)
                        .background(value.wrappedValue == choice.0 ? Palette.blush : Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(PressStyle()).accessibilityValue(value.wrappedValue == choice.0 ? "선택됨" : "선택 안 됨")
            }
        }
    }
    private func save() async {
        saving = true; defer { saving = false }
        do { _ = try await BackendClient.request("v1/calls/\(callID.uuidString)/feedback", body: ["openingEngaging": firstLine, "appStopped": stopped, "wantsTomorrow": tomorrow]); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("이 기록은 기기 안에만 있어요. 감지와 수신 표시, 음성 연결은 각각 따로 확인합니다.").font(.subheadline)
                    Text(SharedResources.automaticDispatchApproved ? "자동 전송 승인 설정 있음 · 허용 문서와 실기기 시험을 함께 확인하세요" : "자동 전송 잠김 · Apple 확인 대기")
                        .font(.caption).foregroundStyle(Palette.rose)
                    if let error = model.state.lastMonitorError { Text(error).font(.caption) }
                }
                #if DEBUG && targetEnvironment(simulator)
                Section {
                    Button("시뮬레이터 전화 받기 시험") {
                        dismiss()
                        Task { await model.calls.manualCall(simulatorPreview: true) }
                    }.disabled(!model.backendConnected || model.isWorking || model.calls.isBusy)
                } header: {
                    Text("개발용 시뮬레이터 시험")
                } footer: {
                    Text("실제 서버에 수동 통화를 요청합니다. 받기를 누르면 AI 음성 연결을 시도합니다. 시스템 CallKit 수신 화면은 실기기에서 따로 확인해야 합니다.")
                }
                #endif
                Section("최근 감지") {
                    if model.state.detections.isEmpty { Text("아직 감지 기록이 없어요. 실기기에서 선택한 앱을 사용해 시험해 주세요.").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(model.state.detections.reversed()) { detection in
                        VStack(alignment: .leading, spacing: 6) {
                            if let app = model.state.apps.first(where: { $0.id == detection.appID }), let token = ScreenTimeScheduler.token(app) { Label(token) }
                            Text(detection.kind == .first ? "첫 한도 감지" : "추가 사용 감지").font(.subheadline)
                            Text(detection.at, style: .time).font(.caption)
                            Text(detection.result).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("수신과 음성") {
                    ForEach(model.state.callHistory) { call in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(call.characterName) · \(outcomeLabel(call.outcome))").font(.subheadline)
                            Text(call.startedAt, style: .date).font(.caption)
                            if let delay = call.arrivalDelaySeconds { Text(String(format: "요청에서 앱 수신까지 %.1f초", delay)).font(.caption) }
                            Text(call.voiceConnectedAt == nil ? "음성 연결 기록 없음" : "WebRTC 연결 기록 있음 · 실제 들리는지는 실기기 시험 필요").font(.caption).foregroundStyle(.secondary)
                            if let answered = call.answeredAt, let connected = call.voiceConnectedAt {
                                Text(String(format: "받기 → WebRTC 준비 %.1f초", max(0, connected.timeIntervalSince(answered)))).font(.caption)
                            }
                            if let answered = call.answeredAt, let output = call.firstOutputTranscriptAt {
                                Text(String(format: "받기 → 첫 AI 발화 신호 %.1f초", max(0, output.timeIntervalSince(answered)))).font(.caption)
                            }
                            if let output = call.firstOutputTranscriptAt, let reply = call.firstUserReplyAt {
                                Text(String(format: "첫 AI 발화 신호 → 첫 사용자 발화 신호 %.1f초", max(0, reply.timeIntervalSince(output)))).font(.caption)
                            }
                            if let answered = call.answeredAt, let packet = call.firstRemoteAudioPacketAt {
                                Text(String(format: "받기 → 첫 원격 음성 패킷 %.1f초", max(0, packet.timeIntervalSince(answered)))).font(.caption)
                                Text("음성 패킷 수신은 스피커에서 들렸다는 증거가 아니에요.").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }.navigationTitle("시험 기록")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .onAppear { model.refresh() }
        }
    }
}
