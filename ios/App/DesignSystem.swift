import SwiftUI
import JiminCore

enum Palette {
    static let paper = Color(hex: 0x18151F)
    static let surface = Color(hex: 0x27232F)
    static let ink = Color(hex: 0xF7F1FA)
    static let muted = Color(hex: 0xB4AABD)
    static let rose = Color(hex: 0xCCBCF4)
    static let blush = Color(hex: 0x363041)
    static let peach = Color(hex: 0xF0BDA7)
    static let sage = Color(hex: 0xA0D1BE)
    static let line = Color(hex: 0x443C4E)
    static let warning = Color(hex: 0xE9C995)
    static let warningBackground = Color(hex: 0x352C27)
    static let danger = Color(hex: 0xDB6B83)
    static let callBackground = paper
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

struct PrimaryButton: View {
    let title: String
    var icon = "phone.fill"
    var disabled = false
    var loading = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if loading { ProgressView().tint(Palette.paper) }
                else if !icon.isEmpty { Image(systemName: icon).font(.body.weight(.semibold)) }
                Text(title).font(.headline).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).frame(minHeight: 56)
            .padding(.horizontal, 16).padding(.vertical, 2).foregroundStyle(disabled ? Palette.muted : Palette.paper)
            .background(disabled ? Palette.surface : Palette.rose, in: Capsule())
        }.buttonStyle(PressStyle()).disabled(disabled).accessibilityLabel(title)
    }
}
struct SecondaryButton: View {
    let title: String
    var icon = ""
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if !icon.isEmpty { Image(systemName: icon) }
                Text(title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).frame(minHeight: 48).padding(.horizontal, 12).foregroundStyle(Palette.rose)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
        }.buttonStyle(PressStyle())
    }
}
struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
struct Surface<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}
struct ScreenHeading: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title.weight(.bold)).tracking(-0.7).accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(3) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct SectionHeading: View {
    let title: String
    var detail: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            if let detail { Text(detail).font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(3) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct StatusPill: View {
    let title: String
    var icon = "checkmark.circle.fill"
    var color = Palette.rose
    var body: some View {
        Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 11).padding(.vertical, 8).background(color.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}
struct InlineNotice: View {
    let title: String
    var detail: String?
    var icon = "info.circle"
    var warning = false
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon).font(.body).padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                if let detail { Text(detail).font(.caption).lineSpacing(3) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(warning ? Palette.warning : Palette.muted).padding(16)
        .background(warning ? Palette.warningBackground : Palette.blush.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
struct CharacterAvatar: View {
    var size: CGFloat = 96
    var body: some View {
        Image("CharacterScene").resizable().scaledToFill()
            .frame(width: size, height: size * 1.5)
            .frame(width: size, height: size, alignment: .top).clipped()
            .clipShape(Circle()).overlay(Circle().stroke(Palette.line, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

struct CharacterScene: View {
    var dimmed = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("CharacterScene").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top).clipped()
                LinearGradient(stops: [
                    .init(color: Palette.paper.opacity(dimmed ? 0.82 : 0.72), location: 0),
                    .init(color: Palette.paper.opacity(dimmed ? 0.70 : 0.62), location: dimmed ? 0.18 : 0.12),
                    .init(color: Palette.paper.opacity(dimmed ? 0.14 : 0), location: dimmed ? 0.40 : 0.28),
                    .init(color: Palette.paper.opacity(dimmed ? 0.12 : 0), location: 0.42),
                    .init(color: Palette.paper.opacity(0.74), location: 0.68),
                    .init(color: Palette.paper, location: 0.94)
                ], startPoint: .top, endPoint: .bottom)
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}
struct SettingRow: View {
    let title: String
    var value: String?
    var icon: String
    var color = Palette.rose
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.body.weight(.medium)).foregroundStyle(color)
                .frame(width: 36, height: 36).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            Text(title).font(.body).foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            if let value { Text(value).font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.trailing) }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted.opacity(0.7))
        }.frame(minHeight: 48).contentShape(Rectangle())
    }
}
struct PersonaChoice: View {
    let persona: Persona
    let selected: Bool
    let select: () -> Void
    let preview: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: select) {
                HStack(spacing: 12) {
                    Image(systemName: persona.symbol).font(.title3).frame(width: 34, height: 42)
                        .foregroundStyle(selected ? Palette.rose : Palette.muted)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(persona.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        Text(persona.subtitle).font(.caption).foregroundStyle(Palette.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Palette.rose : Palette.muted).font(.body)
                }.contentShape(Rectangle()).foregroundStyle(Palette.ink)
            }.buttonStyle(.plain).accessibilityLabel(persona.title).accessibilityValue(selected ? "선택됨" : "선택 안 됨")
            Button(action: preview) {
                Image(systemName: "play.fill").font(.caption.weight(.semibold)).foregroundStyle(Palette.rose)
                    .frame(width: 44, height: 44).background(selected ? Palette.surface : Palette.paper, in: Circle())
            }.buttonStyle(PressStyle()).accessibilityLabel("\(persona.title) 말투 미리 듣기")
        }.padding(16).background(selected ? Palette.blush : Palette.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? Palette.rose : .clear, lineWidth: 1))
    }
}
extension Persona {
    var symbol: String { switch self { case .playful: "face.smiling"; case .gentle: "leaf"; case .direct: "sparkle" } }
    var shortTitle: String { switch self { case .playful: "다정한 장난꾸러기"; case .gentle: "차분한 다정함"; case .direct: "솔직한 장난꾸러기" } }
}
func outcomeLabel(_ outcome: CallOutcome) -> String {
    switch outcome {
    case .requested: "전화 준비 중"
    case .ringing: "전화가 왔어요"
    case .answered: "음성 연결 중"
    case .voiceConnected: "함께 이야기했어요"
    case .declined: "받지 않은 전화"
    case .unanswered: "놓친 전화"
    case .failed: "연결되지 않은 전화"
    case .ended: "통화 종료"
    }
}
