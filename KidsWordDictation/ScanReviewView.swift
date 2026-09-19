import SwiftUI

struct ScanReviewData: Identifiable {
    let id = UUID()
    var words: [WordItem]
}

struct ScanReviewView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var selectedCategory: String
    @State private var customCategory: String
    @State private var speechAccent: SpeechAccent = .american
    @State private var drafts: [WordDraft]
    @State private var pendingDeleteIDs: [WordDraft.ID] = []
    @StateObject private var speechService = SpeechService()

    let categories: [String]
    let onSave: (String, String, [WordItem]) -> Void

    init(review: ScanReviewData, categories: [String] = [], onSave: @escaping (String, String, [WordItem]) -> Void) {
        self.categories = categories
        self._title = State(initialValue: "U1 单词")
        self._selectedCategory = State(initialValue: categories.first ?? "")
        self._customCategory = State(initialValue: "")
        self._drafts = State(initialValue: review.words.map { WordDraft(text: $0.text, phonetic: $0.phonetic, britishPhonetic: $0.britishPhonetic, translation: $0.translation, sentence: $0.sentence) })
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section("单元") {
                    TextField("单元名称，例如 U1 单词", text: $title)
                    if !categories.isEmpty {
                        Picker("选择分类", selection: $selectedCategory) {
                            Text("未分类").tag("")
                            ForEach(categories, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                    }
                    TextField("新分类（可选）", text: $customCategory)
                    Picker("发音", selection: $speechAccent) {
                        ForEach(SpeechAccent.allCases) { accent in
                            Text(accent.title).tag(accent)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("识别结果") {
                    ForEach($drafts) { $draft in
                        HStack(spacing: 12) {
                            VStack(spacing: 8) {
                                TextField("word", text: $draft.text)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .onChange(of: draft.text) { _, newValue in
                                        let metadata = MetadataCompletion.mergedMetadata(
                                            for: newValue,
                                            americanPhonetic: draft.phonetic,
                                            britishPhonetic: draft.britishPhonetic,
                                            translation: draft.translation,
                                            sentence: draft.sentence
                                        )
                                        draft.phonetic = metadata.americanPhonetic
                                        draft.britishPhonetic = metadata.britishPhonetic
                                        draft.translation = metadata.translation
                                        draft.sentence = metadata.sentence
                                    }

                                PhoneticEditorFields(
                                    americanPhonetic: $draft.phonetic,
                                    britishPhonetic: $draft.britishPhonetic,
                                    americanPlaceholder: "美式音标",
                                    britishPlaceholder: "英式音标"
                                )

                                TextField("中文释义", text: $draft.translation)

                                TextField("英文例句", text: $draft.sentence)
                                    .textInputAutocapitalization(.sentences)
                                    .autocorrectionDisabled()

                                MetadataCompletionRow(
                                    missingLabels: MetadataCompletion.missingLabels(
                                        americanPhonetic: draft.phonetic,
                                        britishPhonetic: draft.britishPhonetic,
                                        translation: draft.translation
                                    )
                                ) {
                                    let metadata = MetadataCompletion.mergedMetadata(
                                        for: draft.text,
                                        americanPhonetic: draft.phonetic,
                                        britishPhonetic: draft.britishPhonetic,
                                        translation: draft.translation,
                                        sentence: draft.sentence
                                    )
                                    let changed = metadata.americanPhonetic != draft.phonetic
                                        || metadata.britishPhonetic != draft.britishPhonetic
                                        || metadata.translation != draft.translation
                                        || metadata.sentence != draft.sentence
                                    draft.phonetic = metadata.americanPhonetic
                                    draft.britishPhonetic = metadata.britishPhonetic
                                    draft.translation = metadata.translation
                                    draft.sentence = metadata.sentence
                                    return changed
                                }
                            }

                            Button {
                                speechService.speak(draft.text, rate: 0.45, repetitions: 1, accent: speechAccent)
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: "speaker.wave.2.circle")
                                    Text("发音")
                                        .font(.caption2)
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(WordTextNormalizer.normalize(draft.text).isEmpty)
                            .accessibilityLabel("播放 \(draft.text) 的\(speechAccent.title)发音")

                            Button {
                                speechService.speak(draft.sentence, rate: 0.45, repetitions: 1, accent: speechAccent)
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: "quote.bubble")
                                    Text("例句")
                                        .font(.caption2)
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(WordTextNormalizer.normalize(draft.sentence).isEmpty)
                            .accessibilityLabel("播放 \(draft.text) 的例句")

                            Button(role: .destructive) {
                                requestDeleteWord(id: draft.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("删除 \(draft.text)")
                        }
                    }
                    .onDelete { offsets in
                        requestDeleteWords(at: offsets)
                    }

                    Button {
                        drafts.append(WordDraft(text: "", phonetic: "", britishPhonetic: "", translation: "", sentence: ""))
                    } label: {
                        Label("添加一行", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("确认单词")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(title, resolvedCategory, wordItems)
                        dismiss()
                    }
                    .disabled(wordItems.isEmpty)
                }
            }
            .alert("确认删除单词？", isPresented: Binding(
                get: { !pendingDeleteIDs.isEmpty },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteIDs = []
                    }
                }
            )) {
                Button("删除", role: .destructive) {
                    deletePendingWords()
                }
                Button("取消", role: .cancel) {
                    pendingDeleteIDs = []
                }
            } message: {
                Text("删除后不会保存到这个单元。")
            }
        }
        .onDisappear {
            speechService.stop()
        }
    }

    private var wordItems: [WordItem] {
        var seen = Set<String>()
        return drafts
            .map { WordItem(text: $0.text, phonetic: $0.phonetic, britishPhonetic: $0.britishPhonetic, translation: $0.translation, sentence: $0.sentence) }
            .filter { !$0.normalizedText.isEmpty }
            .filter { seen.insert($0.normalizedText).inserted }
    }

    private var resolvedCategory: String {
        let cleanCustomCategory = customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanCustomCategory.isEmpty ? selectedCategory : cleanCustomCategory
    }

    private func requestDeleteWord(id: WordDraft.ID) {
        pendingDeleteIDs = [id]
    }

    private func requestDeleteWords(at offsets: IndexSet) {
        pendingDeleteIDs = offsets.map { drafts[$0].id }
    }

    private func deletePendingWords() {
        let ids = Set(pendingDeleteIDs)
        drafts.removeAll { ids.contains($0.id) }
        pendingDeleteIDs = []
    }
}

private struct WordDraft: Identifiable {
    let id = UUID()
    var text: String
    var phonetic: String
    var britishPhonetic: String
    var translation: String
    var sentence: String
}
