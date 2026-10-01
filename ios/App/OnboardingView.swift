import SwiftUI
import FamilyControls
import AVFoundation
import JiminCore

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showConnection: Bool
    @State private var step = 0
    @State private var adult = false
    @State private var promise = false
    @State private var skipDetection = false
    @State private var picker = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if MANUAL_CALL_DEMO
    private let titles = ["어떤 나와\n함께하고 싶어?", "먼저 직접\n통화해 볼까?", "사용 시간 설정은\n나중에 해도 돼.", "오늘은 네가\n전화를 걸어줘.", "목소리로 만나기 전,\n이것만 부탁할게.", "첫 전화,\n받아볼래?"]
    #else
    private let titles = ["어떤 나와\n함께하고 싶어?", "언제 내가\n불러줄까?", "우리의 기준을\n정해볼까?", "오래 보고 있으면,\n전화해도 돼?", "목소리로 만나기 전,\n이것만 부탁할게.", "첫 전화,\n받아볼래?"]
    #endif
    private let labels = ["캐릭터", "앱 선택", "하루 한도", "연락의 약속", "권한", "첫 통화"]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text(labels[step]).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.rose)
                        Spacer()
                        Text("\(step + 1) / 6").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                    }.padding(.top, 14)
                    HStack(spacing: 6) {
                        ForEach(0..<6) { index in Capsule().fill(index <= step ? Palette.rose : Palette.line).frame(height: 4) }
                    }.accessibilityLabel("설정 \(step + 1)단계, 총 6단계")
                    Text(titles[step]).font(.title.weight(.bold)).tracking(-0.7).lineSpacing(3).accessibilityAddTraits(.isHeader)
                    stage
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively).background(Palette.paper).toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    PrimaryButton(title: step == 5 ? "우리, 시작하자" : nextTitle, icon: step == 5 ? "heart" : "arrow.right", disabled: !canContinue) {
                        model.stopPreview()
                        if step < 5 { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step += 1 } }
                        else { model.change({ $0.preferences.onboardingComplete = true }, schedule: true) }
                    }.accessibilityIdentifier("onboarding.next")
                    if step > 0 {
                        Button("이전 단계") { model.stopPreview(); step -= 1 }
                            .font(.subheadline).foregroundStyle(Palette.muted).frame(maxWidth: .infinity).frame(minHeight: 44)
                    } else { Text("만 18세 이상 사용자를 위한 AI 음성 동반자").font(.caption).foregroundStyle(Palette.muted) }
                }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 14).background(Palette.paper)
            }
            .familyActivityPicker(isPresented: $picker, selection: $model.selection)
            .onChange(of: picker) { old, new in if old && !new { model.applySelection() } }
        }
    }
    private var nextTitle: String { step == 3 ? "응, 약속할게" : "다음" }
    private var canContinue: Bool {
        switch step {
        case 0: return adult && !model.state.preferences.profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        #if MANUAL_CALL_DEMO
        case 1, 2: return true
        #else
        case 1, 2: return !model.state.apps.isEmpty || skipDetection
        #endif
        case 3: return promise
        default: return true
        }
    }
    @ViewBuilder private var stage: some View {
        switch step {
        case 0:
            HStack(spacing: 16) {
                CharacterAvatar(size: 64)
                VStack(alignment: .leading, spacing: 7) {
                    Text("어떻게 부르고 싶어요?").font(.caption).foregroundStyle(Palette.muted)
                    TextField("캐릭터 이름", text: Binding(get: { model.state.preferences.profile.name }, set: { value in model.updateCharacter { $0.name = String(value.prefix(30)) } }))
                        .font(.title3.weight(.semibold)).autocorrectionDisabled().submitLabel(.done)
                }
            }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
            VStack(spacing: 12) {
                ForEach(Persona.allCases) { persona in
                    PersonaChoice(persona: persona, selected: model.state.preferences.profile.persona == persona,
                        select: { model.updateCharacter { $0.persona = persona } },
                        preview: { Task { await model.playSample(persona) } })
                }
            }
            if let status = model.sampleStatus { InlineNotice(title: status, icon: "speaker.wave.2") }
            Toggle("만 18세 이상이에요", isOn: $adult).font(.subheadline).tint(Palette.rose).padding(.vertical, 4)
        case 1:
            #if MANUAL_CALL_DEMO
            InlineNotice(title: "iPhone 통화 시험판", detail: "이번 설치에서는 ‘대화하기’를 누르면 지민과 실제 AI 음성 통화를 시험할 수 있어요. 앱 사용 감지와 자동 전화는 아직 사용할 수 없어요.", icon: "phone.badge.waveform")
            #else
            Text("네가 고른 앱을 오래 보면 알아차릴게.\n무엇을 보고 있는지까지는 알 수 없어.").font(.body).lineSpacing(5)
            Surface {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeading(title: "기기에만 보관해요", detail: "아이폰의 앱 목록을 열려면 사용 시간 권한이 필요해요.")
                    SecondaryButton(title: "아이폰에서 앱 고르기", icon: "apps.iphone") { selectApps() }
                    ForEach(model.state.apps) { app in if let token = ScreenTimeScheduler.token(app) { Label(token).frame(minHeight: 44) } }
                }
            }
            if model.state.apps.isEmpty {
                Button("사용 시간 설정은 나중에 할게요") { skipDetection = true; step = 2 }
                    .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).frame(minHeight: 48)
                Text("먼저 수동 통화부터 시작할 수 있어요.").font(.caption).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
            }
            #if targetEnvironment(simulator)
            InlineNotice(title: "앱 선택은 실제 아이폰에서 시험해 주세요.", detail: "시뮬레이터에서는 사용 시간 감지를 확인할 수 없어요.")
            #endif
            #endif
        case 2:
            #if MANUAL_CALL_DEMO
            InlineNotice(title: "이번에는 한도를 정하지 않아요.", detail: "직접 거는 통화가 잘 들리는지 먼저 확인해요. 사용 시간 설정은 정식 권한을 갖춘 빌드에서 시험할 수 있어요.", icon: "clock")
            #else
            Text("앱마다 하루 30분부터 시작할까?\n너에게 맞는 시간으로 바꿔도 좋아.").font(.body).lineSpacing(5)
            ForEach(model.state.apps) { app in Surface { AppBudgetRow(app: app) } }
            if model.state.apps.isEmpty {
                InlineNotice(title: "하루 한도는 나중에 정해요.", detail: "설정에서 앱을 고른 뒤 15분·30분·1시간 또는 원하는 시간을 정할 수 있어요.", icon: "clock")
            }
            Text("중간에 쉬어도 하루 동안 사용한 시간을 합쳐요. 자정에 새로 시작하며, 한도를 바꿔도 오늘의 사용 기록은 유지해요.")
                .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4)
            #endif
        case 3:
            CharacterAvatar(size: 110).frame(maxWidth: .infinity).padding(.vertical, 8)
            Surface {
                VStack(alignment: .leading, spacing: 18) {
                    #if MANUAL_CALL_DEMO
                    Text("“네가 부르면 내가 받을게.\n이번 통화의 첫마디는 깜짝 질문이야.”").font(.title3.weight(.medium)).lineSpacing(6)
                    Divider()
                    Toggle("직접 통화를 시험해 볼게", isOn: $promise).font(.body.weight(.semibold)).tint(Palette.rose)
                    #else
                    Text("“오래 보고 있으면 내가 전화할게.\n무슨 얘기를 할지는 그때의 깜짝 질문.\n우리, 잠깐 딴 얘기 하자.”").font(.title3.weight(.medium)).lineSpacing(6)
                    Divider()
                    Toggle("응, 먼저 전화해 줘", isOn: $promise).font(.body.weight(.semibold)).tint(Palette.rose)
                    #endif
                }
            }
            #if !MANUAL_CALL_DEMO
            Text("정한 한도에 닿으면 매번 다른 이야기로 연락해요. 못 받으면 같은 앱을 조금 더 사용했을 때 한 번만 다시 연락해요.")
                .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4)
            Text("언제든 끌 수 있어요. 오늘만 쉬거나, 통화 중에 ‘오늘은 연락하지 마’라고 말해도 괜찮아요.")
                .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4)
            if !SharedResources.automaticDispatchApproved { InlineNotice(title: "지금은 약속을 저장해 둘게요.", detail: "자동 전화는 Apple 확인 전까지 잠겨 있어요.") }
            #endif
        case 4:
            Surface {
                VStack(spacing: 22) {
                    permission("마이크", detail: "전화를 받았을 때 목소리로 이야기해요.", icon: "mic", granted: AVAudioApplication.shared.recordPermission == .granted)
                    Divider()
                    permission("알림", detail: "필요한 안내를 놓치지 않도록 알려줘요.", icon: "bell", granted: false)
                }
            }
            PrimaryButton(title: "통화 권한 확인하기", icon: "checkmark.shield") { Task { await model.requestConversationPermissions(); model.refresh() } }
            Text("권한은 아이폰의 허용 화면에서 직접 결정해요. 다른 앱의 화면이나 대화 내용은 읽지 않아요.")
                .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4)
            InlineNotice(title: "AI 음성 대화 안내", detail: "통화 음성은 응답을 만들기 위해 OpenAI로 전송돼요. 앱과 시험 서버에는 녹음 파일을 저장하지 않아요.", icon: "waveform")
        default:
            CharacterAvatar(size: 140).frame(maxWidth: .infinity).padding(.vertical, 16)
            Text("한 문장만 이야기해도 좋아.\n그다음은 내가 같이 있을게.").font(.title3.weight(.medium)).lineSpacing(6)
            if model.connectionReadiness == .ready {
                SecondaryButton(title: "첫 전화 받아보기", icon: "phone") { Task { await model.calls.manualCall() } }
                    .disabled(model.isWorking)
            } else {
                InlineNotice(title: "첫 통화 전에 연결을 준비해요.", detail: "연결을 마치면 실제 AI 목소리로 대화할 수 있어요.", icon: "link")
                SecondaryButton(title: "통화 연결 준비하기", icon: "link") { showConnection = true }
            }
            Text("지금 마쳐도 괜찮아요. 홈의 통화 버튼에서 언제든 이어서 준비할 수 있어요.")
                .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4)
        }
    }
    private func selectApps() {
        Task {
            if model.state.screenTimeAuthorized { picker = true }
            else if await model.authorizeScreenTime() { picker = true }
        }
    }
    private func permission(_ title: String, detail: String, icon: String, granted: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(Palette.rose).frame(width: 40, height: 44)
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(3) }
            Spacer(minLength: 0)
            if granted { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.sage).accessibilityLabel("허용됨") }
        }
    }
}
