import SwiftUI
import FamilyControls
import JiminCore

struct AppBudgetRow: View {
    @EnvironmentObject private var model: AppModel
    let app: MonitoredApp
    @State private var custom = false
    @State private var minutes = ""
    @State private var invalid = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if let token = ScreenTimeScheduler.token(app) { Label(token).labelStyle(.titleAndIcon) }
                Spacer()
                Text("하루 \(app.dailyMinutes)분").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.rose)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { presets }
                VStack(alignment: .leading, spacing: 8) { HStack(spacing: 8) { preset(15); preset(30); preset(60) }; customButton }
            }
        }.padding(.vertical, 8)
            .sheet(isPresented: $custom) {
                NavigationStack {
                    Form {
                        Section("하루 누적 사용 한도") { TextField("분 단위로 입력", text: $minutes).keyboardType(.numberPad) }
                        if invalid { Text("1분부터 1,440분 사이로 입력해 주세요.").foregroundStyle(Palette.danger) }
                        Section { Text("오늘 사용한 시간과 통화 횟수는 그대로 유지돼요.").font(.subheadline).foregroundStyle(Palette.muted) }
                    }.navigationTitle("직접 설정").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("취소") { custom = false } }
                            ToolbarItem(placement: .confirmationAction) { Button("저장") {
                                guard let value = Int(minutes), (1...1440).contains(value) else { invalid = true; return }
                                model.setBudget(app.id, minutes: value); custom = false
                            } }
                        }
                }.presentationDetents([.medium])
            }
    }
    @ViewBuilder private var presets: some View { preset(15); preset(30); preset(60); customButton }
    private func preset(_ value: Int) -> some View {
        Button(value == 60 ? "1시간" : "\(value)분") { model.setBudget(app.id, minutes: value) }
            .font(.subheadline.weight(.medium)).foregroundStyle(app.dailyMinutes == value ? Palette.rose : Palette.muted)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(app.dailyMinutes == value ? Palette.blush : Palette.paper, in: Capsule())
            .accessibilityValue(app.dailyMinutes == value ? "선택됨" : "선택 안 됨")
    }
    private var customButton: some View {
        Button("직접") { minutes = String(app.dailyMinutes); invalid = false; custom = true }
            .font(.subheadline.weight(.medium)).foregroundStyle(Palette.rose).padding(.horizontal, 12).frame(minHeight: 44)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showConnection: Bool
    @State private var picker = false
    @State private var showDiagnostics = false
    @State private var character = false
    @State private var retry = false
    @State private var permissions = false
    @State private var details = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ScreenHeading(title: "설정", subtitle: "목소리와 연락의 약속").padding(.top, 14)
                    Button { character = true } label: {
                        Surface {
                            HStack(spacing: 16) {
                                CharacterAvatar(size: 58)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(model.state.preferences.profile.name).font(.title3.weight(.bold)).foregroundStyle(Palette.ink)
                                    Text(model.state.preferences.profile.persona.shortTitle).font(.subheadline).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                            }
                        }
                    }.buttonStyle(PressStyle()).accessibilityLabel("캐릭터 이름, 성격과 목소리 변경")
                    #if MANUAL_CALL_DEMO
                    InlineNotice(title: "직접 거는 통화만 시험할 수 있어요.", detail: "앱 사용 감지와 자동 전화는 이 개발 빌드에서 사용할 수 없어요. 홈의 ‘대화하기’로 음성을 확인해 주세요.", icon: "phone.badge.waveform")
                    #else
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: "연락의 약속")
                        Surface {
                            VStack(alignment: .leading, spacing: 16) {
                                Toggle(isOn: Binding(get: { model.state.preferences.proactiveEnabled }, set: model.setProactive)) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("먼저 전화하기").font(.body.weight(.medium))
                                        Text("정한 한도를 넘으면 연락해요").font(.caption).foregroundStyle(Palette.muted)
                                    }
                                }.tint(Palette.rose)
                                Divider().overlay(Palette.line)
                                Button { model.pauseToday() } label: {
                                    HStack {
                                        Label(paused ? "오늘은 쉬는 중" : "오늘은 쉬기", systemImage: paused ? "moon.zzz" : "moon")
                                        Spacer()
                                        Text(paused ? "내일 다시" : "오늘만").font(.caption).foregroundStyle(Palette.muted)
                                    }.font(.subheadline.weight(.medium)).frame(minHeight: 44)
                                }.disabled(paused).foregroundStyle(paused ? Palette.muted : Palette.rose)
                                if !SharedResources.automaticDispatchApproved {
                                    InlineNotice(title: "자동 전화는 Apple 확인을 기다려요.", detail: "지금은 직접 거는 통화를 시험해요. 정한 약속은 저장해 둘게요.", icon: "phone.badge.waveform")
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: "앱별 하루 한도", detail: "중간에 쉬어도 오늘 사용한 시간을 합쳐요.")
                        Surface {
                            VStack(alignment: .leading, spacing: 16) {
                                if model.state.apps.isEmpty {
                                    HStack(alignment: .top, spacing: 13) {
                                        Image(systemName: "apps.iphone").font(.title2).foregroundStyle(Palette.rose)
                                        VStack(alignment: .leading, spacing: 7) {
                                            Text("어떤 앱에서 불러줄까요?").font(.subheadline.weight(.semibold))
                                            Text("앱을 고르고, 앱마다 원하는 시간을 정해요.").font(.caption).foregroundStyle(Palette.muted).lineSpacing(3)
                                        }
                                    }
                                }
                                ForEach(model.state.apps) { AppBudgetRow(app: $0) }
                                SecondaryButton(title: model.state.apps.isEmpty ? "감지할 앱 고르기" : "앱 선택 바꾸기", icon: "plus") { selectApps() }
                                if !model.state.screenTimeAuthorized { Text("사용 시간 권한이 필요해요. 선택한 정보는 기기에만 보관해요.").font(.caption).foregroundStyle(Palette.muted) }
                            }
                        }
                    }
                    Surface(padding: 16) {
                        VStack(spacing: 8) {
                            Button { retry = true } label: { SettingRow(title: "못 받았을 때", value: model.state.preferences.retryEnabled ? "추가 \(model.state.preferences.retryMinutes)분" : "재전화 안 함", icon: "phone.arrow.up.right") }
                            Divider().padding(.leading, 48)
                            Button { character = true } label: { SettingRow(title: "성격과 목소리", value: model.state.preferences.profile.voice.capitalized, icon: "waveform") }
                        }.buttonStyle(.plain)
                    }
                    #endif
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: "연결과 권한")
                        Surface(padding: 16) {
                            VStack(spacing: 8) {
                                Button { showConnection = true } label: { SettingRow(title: "통화 연결", value: model.connectionReadiness.label, icon: "link") }
                                Divider().padding(.leading, 48)
                                Button { permissions = true } label: { SettingRow(title: "마이크와 알림", icon: "mic") }
                            }.buttonStyle(.plain)
                        }
                    }
                    DisclosureGroup("개인정보와 시험 기록", isExpanded: $details) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("선택한 앱과 사용 정보는 기기에만 보관해요. 통화 음성은 AI 응답을 위해 OpenAI로 전송되며, 앱과 시험 서버에 녹음 파일은 저장하지 않아요.")
                            Text("하루 기준은 자정에 바뀌어요. 일부 앱은 연결된 웹사이트의 사용도 합산될 수 있어요.")
                            Button("이 기기의 시험 기록 보기") { showDiagnostics = true }.frame(minHeight: 44)
                        }.font(.caption).foregroundStyle(Palette.muted).lineSpacing(3).padding(.top, 12)
                    }.font(.subheadline).tint(Palette.muted)
                }.padding(.horizontal, 24).padding(.bottom, 28)
            }.background(Palette.paper).toolbar(.hidden, for: .navigationBar)
                .familyActivityPicker(isPresented: $picker, selection: $model.selection)
                .onChange(of: picker) { old, new in if old && !new { model.applySelection() } }
                .sheet(isPresented: $showDiagnostics) { DiagnosticsView() }
                .sheet(isPresented: $character) { CharacterSettingsView() }
                .sheet(isPresented: $retry) { retrySheet }
                .sheet(isPresented: $permissions) { permissionsSheet }
        }
    }
    private var paused: Bool { model.state.preferences.pausedDay == model.state.day }
    private func selectApps() {
        Task {
            if model.state.screenTimeAuthorized { picker = true }
            else if await model.authorizeScreenTime() { picker = true }
        }
    }
    private var retrySheet: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("못 받으면 한 번 더 전화", isOn: Binding(get: { model.state.preferences.retryEnabled }, set: model.setRetry)).tint(Palette.rose)
                    Stepper("추가 \(model.state.preferences.retryMinutes)분 사용 후", value: Binding(get: { model.state.preferences.retryMinutes }, set: { value in model.change { $0.preferences.retryMinutes = value } }), in: 5...120, step: 5)
                        .disabled(!model.state.preferences.retryEnabled)
                } footer: { Text("첫 전화를 거절하거나 놓친 뒤 같은 앱을 더 사용하면 한 번만 다시 전화해요. 전화를 받으면 그 앱 때문에 오늘 다시 연락하지 않아요.") }
                Section { Text("오늘 이미 등록된 재전화 기준은 그대로 유지하고, 변경한 시간은 다음 등록부터 적용돼요.").font(.subheadline).foregroundStyle(Palette.muted) }
            }.navigationTitle("못 받았을 때").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { retry = false } } }
        }.presentationDetents([.medium, .large])
    }
    private var permissionsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionHeading(title: "목소리로 함께하려면", detail: "통화할 때 마이크를 사용하고, 필요한 안내를 알림으로 보내요.")
                    InlineNotice(title: "마이크와 알림", detail: "다른 앱의 내용이나 화면은 읽지 않아요.", icon: "checkmark.shield")
                    PrimaryButton(title: "권한 확인하기", icon: "mic") { Task { await model.requestConversationPermissions() } }
                    Link("아이폰 설정에서 변경", destination: URL(string: UIApplication.openSettingsURLString)!)
                        .font(.subheadline).frame(minHeight: 44)
                }.padding(24)
            }.background(Palette.paper).navigationTitle("마이크와 알림").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { permissions = false } } }
        }.presentationDetents([.medium, .large])
    }
}

struct CharacterSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CharacterProfile()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 18) { CharacterAvatar(size: 72); SectionHeading(title: "너에게 어울리는 목소리", detail: "변경한 설정은 다음 통화부터 적용해요.") }
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            labeledField("이름", value: Binding(get: { draft.name }, set: { draft.name = String($0.prefix(30)) }))
                            Divider()
                            labeledField("나를 부르는 호칭", value: Binding(get: { draft.nickname }, set: { draft.nickname = String($0.prefix(30)) }))
                        }
                    }
                    if !validNames { InlineNotice(title: "이름과 호칭을 적어 주세요.", detail: "각각 30자까지 사용할 수 있어요.", icon: "pencil") }
                    SectionHeading(title: "성격", detail: "재생 버튼으로 말투를 먼저 들어보세요.")
                    VStack(spacing: 12) {
                        ForEach(Persona.allCases) { persona in PersonaChoice(persona: persona, selected: draft.persona == persona,
                            select: { draft.persona = persona }, preview: { Task { await model.playSample(persona, profile: draft) } }) }
                    }
                    if let status = model.sampleStatus { InlineNotice(title: status, icon: "speaker.wave.2") }
                    Surface {
                        HStack {
                            Text("목소리").font(.body)
                            Spacer()
                            Picker("목소리", selection: $draft.voice) {
                                Text("Marin").tag("marin"); Text("Coral").tag("coral"); Text("Shimmer").tag("shimmer")
                            }.pickerStyle(.menu).labelsHidden()
                        }
                    }
                }.padding(24)
            }.background(Palette.paper).navigationTitle("캐릭터").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { model.stopPreview(); dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("완료") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        draft.nickname = draft.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.updateCharacter { $0 = draft }; model.stopPreview(); dismiss()
                    }.disabled(!validNames) }
                }
                .onAppear { draft = model.state.preferences.profile }
                .onDisappear { model.stopPreview() }
        }
    }
    private var validNames: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private func labeledField(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.caption).foregroundStyle(Palette.muted); TextField(title, text: value).font(.body).autocorrectionDisabled().submitLabel(.done) }
    }
}
