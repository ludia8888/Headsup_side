import SwiftUI
import JiminCore

enum AppTab: String, CaseIterable {
    case ai = "AI", together = "우리", settings = "설정"
    var symbol: String { switch self { case .ai: "waveform"; case .together: "heart"; case .settings: "slider.horizontal.3" } }
}
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var calls = CallCoordinator.shared
    @State private var tab = AppTab.ai
    @State private var showConnection = false
    var body: some View {
        Group {
            if model.state.preferences.onboardingComplete {
                VStack(spacing: 0) {
                    Group {
                        switch tab {
                        case .ai: AIHomeView(showConnection: $showConnection)
                        case .together: TogetherView()
                        case .settings: SettingsView(showConnection: $showConnection)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    tabBar
                    }
            } else { OnboardingView(showConnection: $showConnection) }
        }
        .foregroundStyle(Palette.ink).background(Palette.paper)
        .sheet(isPresented: $showConnection) { ConnectionView() }
        .fullScreenCover(isPresented: Binding(get: { calls.isBusy }, set: { _ in })) { ActiveCallView().environmentObject(model) }
        .sheet(isPresented: Binding(get: { calls.feedbackCallID != nil && !calls.isBusy }, set: { if !$0 { calls.feedbackCallID = nil } })) {
            if let id = calls.feedbackCallID { FeedbackView(callID: id) }
        }
        .alert("확인이 필요해요", isPresented: Binding(get: { model.errorMessage != nil && !calls.isBusy && !showConnection }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("확인", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .task { await model.checkConnection() }
    }
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { item in
                Button { tab = item } label: {
                    VStack(spacing: 7) {
                        Image(systemName: item.symbol).font(.system(size: 21, weight: tab == item ? .semibold : .regular))
                        Text(item.rawValue).font(.caption.weight(tab == item ? .semibold : .regular))
                    }
                    .foregroundStyle(tab == item ? Palette.rose : Palette.muted.opacity(0.75))
                    .frame(maxWidth: .infinity).frame(minHeight: 54)
                }.buttonStyle(PressStyle()).accessibilityLabel(item.rawValue)
                    .accessibilityValue(tab == item ? "선택된 탭" : "탭").accessibilityIdentifier("tab.\(item.rawValue)")
            }
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
            .background(Palette.paper.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(Palette.line.opacity(0.45)).frame(height: 0.5) }
    }
}
struct AIHomeView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showConnection: Bool
    @State private var character = false
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    CharacterScene().ignoresSafeArea(edges: .top)
                    VStack(spacing: 0) {
                        GeometryReader { viewport in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) {
                                    identity.padding(.top, 14)
                                    Spacer(minLength: 180)
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(message).font(.title3.weight(.semibold)).lineSpacing(5)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text("선택한 말투의 한마디").font(.caption).foregroundStyle(Palette.muted)
                                    }.padding(.top, 20).padding(.bottom, 24)
                                }
                                .padding(.horizontal, 24).frame(minHeight: viewport.size.height, alignment: .top)
                            }.scrollIndicators(.hidden).refreshable { model.refresh(); await model.checkConnection() }
                        }
                        VStack(spacing: 22) {
                            callAction
                            if let recent = model.state.callHistory.first {
                                HStack(spacing: 10) {
                                    Image(systemName: recent.voiceConnectedAt == nil ? "phone.arrow.down.left" : "phone.fill")
                                        .font(.subheadline).foregroundStyle(Palette.muted)
                                    Text(outcomeLabel(recent.outcome)).font(.caption).foregroundStyle(Palette.muted)
                                    Spacer(minLength: 8)
                                    Text(recent.startedAt, style: .relative).font(.caption).foregroundStyle(Palette.muted)
                                }.frame(minHeight: 30).accessibilityElement(children: .combine)
                            }
                        }.padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 22)
                    }
                }.background(Palette.paper)
            }.toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $character) { CharacterSettingsView() }
        }
    }
    private var identity: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Text(model.state.preferences.profile.name).font(.title.weight(.bold)).tracking(-0.5)
                        .lineLimit(2).accessibilityAddTraits(.isHeader)
                    Text("AI").font(.caption2.weight(.semibold)).foregroundStyle(Palette.ink.opacity(0.85))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Palette.paper.opacity(0.5), in: Capsule())
                }
                Text(model.state.preferences.profile.persona.shortTitle).font(.caption).foregroundStyle(Palette.ink.opacity(0.8))
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { character = true } label: {
                Image(systemName: "slider.horizontal.3").font(.body)
                    .foregroundStyle(Palette.ink).frame(width: 44, height: 44)
                    .background(Palette.paper.opacity(0.5), in: Circle())
                    .overlay(Circle().stroke(Palette.ink.opacity(0.12), lineWidth: 0.5))
            }.buttonStyle(PressStyle()).accessibilityLabel("캐릭터 이름, 성격과 목소리 변경")
        }
    }
    private var callAction: some View {
        VStack(spacing: 12) {
            PrimaryButton(title: actionTitle, disabled: model.isWorking || model.checkingConnection, loading: model.isWorking || model.checkingConnection) {
                if model.connectionReadiness == .ready { Task { await model.calls.manualCall() } }
                else { showConnection = true }
            }.accessibilityIdentifier("home.call")
            Text(actionDetail).font(.caption).foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
    }
    private var actionTitle: String {
        if model.isWorking { return "전화 준비 중" }
        if model.checkingConnection { return "연결 확인 중" }
        switch model.connectionReadiness {
        case .ready: return "대화하기"
        case .notConnected: return "통화 연결하기"
        case .needsKey, .unavailable: return "통화 연결 확인"
        }
    }
    private var actionDetail: String {
        switch model.connectionReadiness {
        case .ready: return "다음엔 어떤 이야기를 하게 될까요?"
        case .notConnected: return "첫 전화 전에 연결을 준비해요."
        case .needsKey: return "음성 설정을 마치면 통화할 수 있어요."
        case .unavailable: return "통화 연결을 다시 확인해 주세요."
        }
    }
    private var message: String {
        switch model.state.preferences.profile.persona {
        case .playful: return "오늘은 조금 엉뚱한\n얘기를 해볼까?"
        case .gentle: return "네 하루에 잠깐,\n다른 이야기를 더해볼까?"
        case .direct: return "아, 갑자기 궁금해졌어.\n우리 딴 얘기 좀 할까?"
        }
    }
}
