import SwiftUI

struct AddWordListView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var selectedCategory: String
    @State private var customCategory = ""
    @State private var rawWords = ""
    @State private var newWord = ""
    @State private var newPhonetic = ""
    @State private var newBritishPhonetic = ""
    @State private var newTranslation = ""
    @State private var newSentence = ""
    @State private var newWordAccent: SpeechAccent = .american
    @State private var drafts: [ManualWordDraft] = []
    @State private var pendingDeleteIDs: [ManualWordDraft.ID] = []
    @StateObject private var speechService = SpeechService()

    let categories: [String]
    let onSave: (String, String, [WordItem]) -> Void

    init(categories: [String] = [], onSave: @escaping (String, String, [WordItem]) -> Void) {
        self.categories = categories
        self.onSave = onSave
        self._selectedCategory = State(initialValue: categories.first ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
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
                }

                Section("追加单词") {
                    TextField("英文单词或短语", text: $newWord)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: newWord) { _, newValue in
                            let metadata = MetadataCompletion.mergedMetadata(
                                for: newValue,
                                americanPhonetic: newPhonetic,
                                britishPhonetic: newBritishPhonetic,
                                translation: newTranslation,
                                sentence: newSentence
                            )
                            newPhonetic = metadata.americanPhonetic
                            newBritishPhonetic = metadata.britishPhonetic
                            newTranslation = metadata.translation
                            newSentence = metadata.sentence
                        }

                    PhoneticEditorFields(
                        americanPhonetic: $newPhonetic,
                        britishPhonetic: $newBritishPhonetic
                    )

                    TextField("中文释义", text: $newTranslation)

                    TextField("英文例句", text: $newSentence)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()

                    MetadataCompletionRow(
                        missingLabels: MetadataCompletion.missingLabels(
                            americanPhonetic: newPhonetic,
                            britishPhonetic: newBritishPhonetic,
                            translation: newTranslation
                        )
                    ) {
                        let metadata = MetadataCompletion.mergedMetadata(
                            for: newWord,
                            americanPhonetic: newPhonetic,
                            britishPhonetic: newBritishPhonetic,
                            translation: newTranslation,
                            sentence: newSentence
                        )
                        let changed = metadata.americanPhonetic != newPhonetic
                            || metadata.britishPhonetic != newBritishPhonetic
                            || metadata.translation != newTranslation
                            || metadata.sentence != newSentence
                        newPhonetic = metadata.americanPhonetic
                        newBritishPhonetic = metadata.britishPhonetic
                        newTranslation = metadata.translation
                        newSentence = metadata.sentence
                        return changed
                    }

                    Picker("发音", selection: $newWordAccent) {
                        ForEach(SpeechAccent.allCases) { accent in
                            Text(accent.title).tag(accent)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        Button {
                            speechService.speak(newWord, rate: 0.45, repetitions: 1, accent: newWordAccent)
                        } label: {
                            Label("\(newWordAccent.title)发音", systemImage: "speaker.wave.2")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(WordTextNormalizer.normalize(newWord).isEmpty)

                        Button {
                            speechService.speak(newSentence, rate: 0.45, repetitions: 1, accent: newWordAccent)
                        } label: {
                            Label("播放例句", systemImage: "quote.bubble")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(WordTextNormalizer.normalize(newSentence).isEmpty)
                    }

                    Button {
                        addNewWord()
                    } label: {
                        Label("添加到列表", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(WordTextNormalizer.normalize(newWord).isEmpty)
                }

                Section("批量粘贴导入") {
                    TextEditor(text: $rawWords)
                        .frame(minHeight: 120)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        appendExtractedWords()
                    } label: {
                        Label("提取并追加到单词列表", systemImage: "text.badge.plus")
                    }
                    .disabled(WordTextExtractor.extractWords(from: rawWords).isEmpty)
                }

                if !wordItems.isEmpty {
                    Section("单词列表") {
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

                                Spacer()

                                Button {
                                    speechService.speak(draft.text, rate: 0.45, repetitions: 1, accent: newWordAccent)
                                } label: {
                                    VStack(spacing: 2) {
                                        Image(systemName: "speaker.wave.2.circle")
                                        Text("发音")
                                            .font(.caption2)
                                    }
                                }
                                .buttonStyle(.borderless)
                                .disabled(WordTextNormalizer.normalize(draft.text).isEmpty)
                                .accessibilityLabel("播放 \(draft.text) 的\(newWordAccent.title)发音")

                                Button {
                                    speechService.speak(draft.sentence, rate: 0.45, repetitions: 1, accent: newWordAccent)
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
                    }
                }
            }
            .navigationTitle("创建单元")
            .onDisappear {
                speechService.stop()
            }
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

    private func addNewWord() {
        appendWords([WordItem(text: newWord, phonetic: newPhonetic, britishPhonetic: newBritishPhonetic, translation: newTranslation, sentence: newSentence)])
        newWord = ""
        newPhonetic = ""
        newBritishPhonetic = ""
        newTranslation = ""
        newSentence = ""
    }

    private func appendExtractedWords() {
        appendWords(WordTextExtractor.extractWords(from: rawWords))
        rawWords = ""
    }

    private func appendWords(_ items: [WordItem]) {
        var existing = Set(drafts.map { WordTextNormalizer.normalize($0.text) })
        for item in items where !item.normalizedText.isEmpty && existing.insert(item.normalizedText).inserted {
            drafts.append(ManualWordDraft(text: item.text, phonetic: item.phonetic, britishPhonetic: item.britishPhonetic, translation: item.translation, sentence: item.sentence))
        }
    }

    private func requestDeleteWord(id: ManualWordDraft.ID) {
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

private struct ManualWordDraft: Identifiable {
    let id = UUID()
    var text: String
    var phonetic: String
    var britishPhonetic: String
    var translation: String
    var sentence: String
}

struct PhoneticEditorFields: View {
    @Binding var americanPhonetic: String
    @Binding var britishPhonetic: String
    @State private var isBritishEditorVisible = false

    let americanPlaceholder: String
    let britishPlaceholder: String

    init(
        americanPhonetic: Binding<String>,
        britishPhonetic: Binding<String>,
        americanPlaceholder: String = "美式音标，例如 /waɪf/",
        britishPlaceholder: String = "英式音标，例如 /waɪf/"
    ) {
        self._americanPhonetic = americanPhonetic
        self._britishPhonetic = britishPhonetic
        self.americanPlaceholder = americanPlaceholder
        self.britishPlaceholder = britishPlaceholder
    }

    var body: some View {
        labeledPhoneticField(label: shouldShowBritishEditor ? "美式" : "美/英", text: $americanPhonetic, placeholder: americanPlaceholder)

        if shouldShowBritishEditor {
            labeledPhoneticField(label: "英式", text: $britishPhonetic, placeholder: britishPlaceholder)
        } else {
            HStack {
                Text("英式音标同美式")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("修改") {
                    isBritishEditorVisible = true
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
    }

    private var shouldShowBritishEditor: Bool {
        isBritishEditorVisible
            || clean(americanPhonetic).isEmpty
            || clean(britishPhonetic).isEmpty
            || clean(americanPhonetic) != clean(britishPhonetic)
    }

    private func clean(_ text: String) -> String {
        WordTextNormalizer.displayText(for: text)
    }

    private func labeledPhoneticField(label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)

            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}
