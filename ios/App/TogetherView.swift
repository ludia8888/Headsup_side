import SwiftUI
import JiminCore

struct TogetherView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editing: ConfirmedMemory?
    @State private var newMemory = false
    @State private var deleting: ConfirmedMemory?
    @State private var text = ""
    @FocusState private var editorFocused: Bool
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ScreenHeading(title: "우리", subtitle: "전화가 끝나도 이어지는 이야기").padding(.top, 14)
                    HStack(spacing: 16) {
                        CharacterAvatar(size: 64)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("\(model.state.preferences.profile.name)과 함께한 \(days)일")
                                .font(.headline).foregroundStyle(Palette.peach)
                            Text("하나씩, 천천히 알아가는 중").font(.caption).foregroundStyle(Palette.muted)
                        }
                        Spacer(minLength: 0)
                    }.padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                    Divider().overlay(Palette.line.opacity(0.5))
                    HStack {
                        SectionHeading(title: "우리의 기억", detail: "네가 확인해 준 이야기만 남겨요.")
                        Button { text = ""; newMemory = true } label: {
                            Image(systemName: "plus").font(.body.weight(.medium)).foregroundStyle(Palette.rose)
                                .frame(width: 44, height: 44).background(Palette.surface, in: Circle())
                        }.accessibilityLabel("기억 추가").accessibilityIdentifier("memory.add")
                    }
                    if model.state.preferences.memories.isEmpty { emptyState }
                    else {
                        VStack(spacing: 0) {
                            ForEach(model.state.preferences.memories) { memory in memoryRow(memory) }
                        }
                    }
                    Label("기억을 수정하거나 지우면 다음 통화부터 반영돼요.", systemImage: "lock")
                        .font(.caption).foregroundStyle(Palette.muted).lineSpacing(3)
                }.padding(.horizontal, 24).padding(.bottom, 28)
            }.background(Palette.paper).toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: Binding(get: { editing != nil || newMemory }, set: { if !$0 { editing = nil; newMemory = false } })) { editor }
                .confirmationDialog("이 기억을 지울까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button("기억 삭제", role: .destructive) { if let deleting { model.deleteMemory(deleting.id) }; deleting = nil }
                    Button("취소", role: .cancel) { deleting = nil }
                } message: { Text("다음 통화부터 이 내용을 기억으로 사용하지 않아요.") }
        }
    }
    private var emptyState: some View {
        Surface(padding: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "book.closed").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.peach)
                    .frame(height: 44)
                Text("처음부터 다 알 필요는 없으니까.").font(.title3.weight(.semibold))
                Text("좋아하는 것, 기억했으면 하는 이야기.\n하나씩 알려줘요. 통화할 때도 이어갈게요.")
                    .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(5)
                Button { text = ""; newMemory = true } label: {
                    Label("첫 기억 남기기", systemImage: "plus").font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.rose).frame(minHeight: 44)
                }.buttonStyle(PressStyle())
            }
        }
    }
    private func memoryRow(_ memory: ConfirmedMemory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
                Text(memory.text).font(.body).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Label("확인한 기억", systemImage: "checkmark.seal").font(.caption).foregroundStyle(Palette.sage)
                    Spacer()
                    Text(memory.confirmedAt, format: .dateTime.month().day()).font(.caption).foregroundStyle(Palette.muted)
                    Menu {
                        Button("기억 수정", systemImage: "pencil") { editing = memory; text = memory.text }
                        Button("기억 삭제", systemImage: "trash", role: .destructive) { deleting = memory }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .accessibilityLabel("이 기억 수정 또는 삭제")
                }
                Divider().overlay(Palette.line.opacity(0.5))
        }.padding(.top, 18)
    }
    private var editor: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("어떤 이야기를 기억할까요?").font(.title2.weight(.bold))
                    Text("확인하고 저장한 내용만 다음 통화에서 사용해요.").font(.subheadline).foregroundStyle(Palette.muted)
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack(alignment: .topLeading) {
                            if text.isEmpty { Text("예: 비 오는 날에는 재즈 듣는 걸 좋아해").font(.body).foregroundStyle(Palette.muted).padding(.top, 12).padding(.leading, 5) }
                            TextEditor(text: $text).focused($editorFocused).scrollContentBackground(.hidden)
                                .frame(minHeight: 160).accessibilityLabel("기억할 내용")
                        }
                        HStack {
                            Spacer()
                            Text("\(text.count) / 500").font(.caption).foregroundStyle(text.count > 500 ? Palette.danger : Palette.muted)
                        }
                    }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(editorFocused ? Palette.rose : Palette.line, lineWidth: 1))
                    InlineNotice(title: "저장하기 전에 한 번 더 확인해 주세요.", detail: "아래 버튼을 누르면 이 내용을 기억하는 데 동의해요.", icon: "checkmark.shield")
                }.padding(24)
            }.background(Palette.paper)
                .navigationTitle(editing == nil ? "기억 추가" : "기억 수정").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { editing = nil; newMemory = false } } }
                .safeAreaInset(edge: .bottom) {
                    PrimaryButton(title: "확인하고 저장", icon: "checkmark", disabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 500) { save() }
                        .padding(24).background(Palette.paper)
                }
        }.presentationDetents([.large])
    }
    private func save() {
        model.errorMessage = nil
        if let editing { model.saveEditedMemory(editing.id, text: text) }
        else {
            let proposal = MemoryProposal(text: text.trimmingCharacters(in: .whitespacesAndNewlines))
            model.pendingMemory = proposal; model.confirmMemory(proposal)
        }
        if model.errorMessage == nil { editing = nil; newMemory = false }
    }
    private var days: Int {
        max(1, (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: model.state.preferences.startedAt), to: Calendar.current.startOfDay(for: Date())).day ?? 0) + 1)
    }
}
