import SwiftUI
import Translation

struct ScanReviewData: Identifiable {
    let id = UUID()
    var words: [WordItem]
}

struct ScanReviewView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var selectedCategory: String
    @State private var customCategory: String
    @AppStorage(SpeechAccent.storageKey) private var accentRawValue = SpeechAccent.american.rawValue
    @State private var drafts: [WordDraft]
    @State private var pendingDeleteIDs: [WordDraft.ID] = []
    @State private var isBatchCompleting = false
    @State private var batchCompletionMessage = ""
    @State private var pendingBatchTranslations: [BatchTranslationRequest] = []
    @State private var batchTranslationConfiguration: TranslationSession.Configuration?
    @State private var didAttemptAutomaticCompletion = false
    @AppStorage(OnlineCompletionSettings.storageKey) private var onlineCompletionEnabled = true
    @StateObject private var speechService = SpeechService()

    let categories: [String]
    let onSave: (String, String, [WordItem]) -> Void

    init(review: ScanReviewData, categories: [String] = [], onSave: @escaping (String, String, [WordItem]) -> Void) {
        self.categories = categories
        self._title = State(initialValue: "U1 单词")
        self._selectedCategory = State(initialValue: categories.first ?? "")
        self._customCategory = State(initialValue: "")
        self._drafts = State(initialValue: review.words.map { WordDraft(text: $0.text, phonetic: $0.phonetic, britishPhonetic: $0.britishPhonetic, translation: $0.translation, sentence: $0.sentence, sentenceTranslation: $0.sentenceTranslation) })
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
                    Picker("发音", selection: accentBinding) {
                        ForEach(SpeechAccent.allCases) { accent in
                            Text(accent.title).tag(accent)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("识别结果") {
                    if hasMissingMetadata {
                        Button {
                            batchCompleteMissingMetadata()
                        } label: {
                            Label(isBatchCompleting ? "批量补全中" : "批量补全缺失项", systemImage: isBatchCompleting ? "hourglass" : "wand.and.stars")
                        }
                        .disabled(isBatchCompleting)

                        if !batchCompletionMessage.isEmpty {
                            Text(batchCompletionMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach($drafts) { $draft in
                        HStack(spacing: 12) {
                            VStack(spacing: 8) {
                                TextField("word", text: $draft.text)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .onChange(of: draft.text) { oldValue, newValue in
                                        guard WordTextNormalizer.normalize(oldValue)
                                                != WordTextNormalizer.normalize(newValue) else { return }
                                        let metadata = WordMetadataProvider.metadata(for: newValue)
                                        draft.phonetic = metadata.americanPhonetic
                                        draft.britishPhonetic = metadata.britishPhonetic
                                        draft.translation = metadata.translation
                                        draft.sentence = metadata.sentence
                                        draft.sentenceTranslation = metadata.sentenceTranslation
                                    }

                                if let suggestion = spellingSuggestion(for: draft.text) {
                                    Button {
                                        applySpellingSuggestion(suggestion, to: draft.id)
                                    } label: {
                                        Label("可能是 \(suggestion)，点击修正", systemImage: "text.magnifyingglass")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
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

                                TextField("例句中文", text: $draft.sentenceTranslation)

                                MetadataCompletionRow(
                                    wordText: draft.text,
                                    americanPhonetic: draft.phonetic,
                                    britishPhonetic: draft.britishPhonetic,
                                    translation: draft.translation,
                                    sentence: draft.sentence,
                                    sentenceTranslation: draft.sentenceTranslation,
                                    missingLabels: MetadataCompletion.missingLabels(
                                        americanPhonetic: draft.phonetic,
                                        britishPhonetic: draft.britishPhonetic,
                                        translation: draft.translation,
                                        sentence: draft.sentence,
                                        sentenceTranslation: draft.sentenceTranslation
                                    )
                                ) { metadata in
                                    let changed = metadata.americanPhonetic != draft.phonetic
                                        || metadata.britishPhonetic != draft.britishPhonetic
                                        || metadata.translation != draft.translation
                                        || metadata.sentence != draft.sentence
                                        || metadata.sentenceTranslation != draft.sentenceTranslation
                                    draft.phonetic = metadata.americanPhonetic
                                    draft.britishPhonetic = metadata.britishPhonetic
                                    draft.translation = metadata.translation
                                    draft.sentence = metadata.sentence
                                    draft.sentenceTranslation = metadata.sentenceTranslation
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
                        drafts.append(WordDraft(text: "", phonetic: "", britishPhonetic: "", translation: "", sentence: "", sentenceTranslation: ""))
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
            .translationTask(batchTranslationConfiguration) { session in
                await runBatchTranslation(session)
            }
            .task {
                guard !didAttemptAutomaticCompletion else { return }
                didAttemptAutomaticCompletion = true
                if hasMissingMetadata {
                    batchCompleteMissingMetadata()
                }
            }
        }
        .onDisappear {
            speechService.stop()
        }
    }

    private var wordItems: [WordItem] {
        var seen = Set<String>()
        return drafts
            .map { WordItem(text: $0.text, phonetic: $0.phonetic, britishPhonetic: $0.britishPhonetic, translation: $0.translation, sentence: $0.sentence, sentenceTranslation: $0.sentenceTranslation) }
            .filter { !$0.normalizedText.isEmpty }
            .filter { seen.insert($0.normalizedText).inserted }
    }

    private var resolvedCategory: String {
        let cleanCustomCategory = customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanCustomCategory.isEmpty ? selectedCategory : cleanCustomCategory
    }

    private var hasMissingMetadata: Bool {
        drafts.contains { draft in
            !MetadataCompletion.missingLabels(
                americanPhonetic: draft.phonetic,
                britishPhonetic: draft.britishPhonetic,
                translation: draft.translation,
                sentence: draft.sentence,
                sentenceTranslation: draft.sentenceTranslation
            ).isEmpty
        }
    }

    private func batchCompleteMissingMetadata(refresh: Bool = false) {
        guard !isBatchCompleting else { return }
        isBatchCompleting = true
        batchCompletionMessage = "正在应用内置词库"
        pendingBatchTranslations = []

        Task { await resolveBatchMetadata(refresh: refresh) }
    }

    @MainActor
    private func resolveBatchMetadata(refresh: Bool) async {

        for index in drafts.indices {
            let resolvedMetadata = MetadataCompletion.mergedMetadata(
                for: drafts[index].text,
                americanPhonetic: drafts[index].phonetic,
                britishPhonetic: drafts[index].britishPhonetic,
                translation: drafts[index].translation,
                sentence: drafts[index].sentence,
                sentenceTranslation: drafts[index].sentenceTranslation
            )
            apply(resolvedMetadata, toDraftAt: index)
        }

        let queryableTexts = drafts
            .map(\.text)
            .filter { spellingSuggestion(for: $0) == nil }
        if onlineCompletionEnabled {
            batchCompletionMessage = "正在查询在线词典，仅发送单个英文词条"
        }
        let resolutions = await WordMetadataCoordinator.shared.resolveMany(
            texts: queryableTexts,
            allowNetwork: onlineCompletionEnabled,
            refresh: refresh
        )

        for index in drafts.indices {
            let key = WordTextNormalizer.normalize(drafts[index].text)
            if let resolution = resolutions[key] {
                let merged = MetadataCompletion.mergingCurrentValues(
                    americanPhonetic: drafts[index].phonetic,
                    britishPhonetic: drafts[index].britishPhonetic,
                    translation: drafts[index].translation,
                    sentence: drafts[index].sentence,
                    sentenceTranslation: drafts[index].sentenceTranslation,
                    with: resolution.metadata
                )
                apply(merged, toDraftAt: index)
            }

            if drafts[index].translation.isEmpty
                || (!drafts[index].sentence.isEmpty && drafts[index].sentenceTranslation.isEmpty) {
                pendingBatchTranslations.append(BatchTranslationRequest(
                    id: drafts[index].id,
                    text: drafts[index].text,
                    metadata: metadata(forDraftAt: index)
                ))
            }
        }

        if pendingBatchTranslations.isEmpty {
            batchCompletionMessage = completionSummary(prefix: onlineCompletionEnabled ? "已完成资料补全" : "已应用内置资料")
            isBatchCompleting = false
        } else {
            batchCompletionMessage = "音标资料已应用，正在使用系统翻译补充中文"
            batchTranslationConfiguration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "zh-Hans")
            )
            batchTranslationConfiguration?.invalidate()
        }
    }

    @MainActor
    private func runBatchTranslation(_ session: TranslationSession) async {
        var failedCount = 0

        do {
            try await session.prepareTranslation()
            for request in pendingBatchTranslations {
                guard let index = drafts.firstIndex(where: { $0.id == request.id }) else {
                    continue
                }
                var metadata = request.metadata
                do {
                    if metadata.translation.isEmpty {
                        let response = try await session.translate(request.text)
                        metadata.translation = WordTextNormalizer.displayText(for: response.targetText)
                    }
                    if !metadata.sentence.isEmpty && metadata.sentenceTranslation.isEmpty {
                        let response = try await session.translate(metadata.sentence)
                        metadata.sentenceTranslation = WordTextNormalizer.displayText(for: response.targetText)
                    }
                    apply(metadata, toDraftAt: index)
                } catch {
                    apply(metadata, toDraftAt: index)
                    failedCount += 1
                }
            }
            let prefix = failedCount == 0 ? "已完成批量补全" : "部分中文翻译暂不可用，可手动编辑"
            batchCompletionMessage = completionSummary(prefix: prefix)
        } catch {
            for request in pendingBatchTranslations {
                if let index = drafts.firstIndex(where: { $0.id == request.id }) {
                    apply(request.metadata, toDraftAt: index)
                }
            }
            batchCompletionMessage = completionSummary(
                prefix: "系统翻译暂不可用：\(error.localizedDescription)。可手动编辑"
            )
        }

        pendingBatchTranslations = []
        isBatchCompleting = false
    }

    private func completionSummary(prefix: String) -> String {
        let missingPhoneticCount = drafts.filter {
            WordTextNormalizer.displayText(for: $0.phonetic).isEmpty
                || WordTextNormalizer.displayText(for: $0.britishPhonetic).isEmpty
        }.count
        guard missingPhoneticCount > 0 else {
            return prefix
        }
        let suggestionCount = drafts.filter { spellingSuggestion(for: $0.text) != nil }.count
        let suggestionSuffix = suggestionCount > 0 ? "；\(suggestionCount) 个词可能识别有误，请先确认拼写" : ""
        return "\(prefix)；\(missingPhoneticCount) 个词仍缺音标，可重新查询或手动编辑\(suggestionSuffix)"
    }

    private func apply(_ metadata: WordMetadata, toDraftAt index: Int) {
        drafts[index].phonetic = metadata.americanPhonetic
        drafts[index].britishPhonetic = metadata.britishPhonetic
        drafts[index].translation = metadata.translation
        drafts[index].sentence = metadata.sentence
        drafts[index].sentenceTranslation = metadata.sentenceTranslation
    }

    private func metadata(forDraftAt index: Int) -> WordMetadata {
        WordMetadata(
            americanPhonetic: drafts[index].phonetic,
            britishPhonetic: drafts[index].britishPhonetic,
            translation: drafts[index].translation,
            sentence: drafts[index].sentence,
            sentenceTranslation: drafts[index].sentenceTranslation
        )
    }

    private func spellingSuggestion(for text: String) -> String? {
        SystemSpellingSuggestionProvider.suggestion(for: text)
    }

    private func applySpellingSuggestion(_ suggestion: String, to id: WordDraft.ID) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].text = suggestion
        let metadata = WordMetadataProvider.metadata(for: suggestion)
        drafts[index].phonetic = metadata.americanPhonetic
        drafts[index].britishPhonetic = metadata.britishPhonetic
        drafts[index].translation = metadata.translation
        drafts[index].sentence = metadata.sentence
        drafts[index].sentenceTranslation = metadata.sentenceTranslation
        batchCompletionMessage = "已修正为 \(suggestion)"
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

    private var speechAccent: SpeechAccent {
        SpeechAccent(rawValue: accentRawValue) ?? .american
    }

    private var accentBinding: Binding<SpeechAccent> {
        Binding(
            get: { speechAccent },
            set: { accentRawValue = $0.rawValue }
        )
    }
}

private struct WordDraft: Identifiable {
    let id = UUID()
    var text: String
    var phonetic: String
    var britishPhonetic: String
    var translation: String
    var sentence: String
    var sentenceTranslation: String
}

private struct BatchTranslationRequest {
    let id: WordDraft.ID
    let text: String
    let metadata: WordMetadata
}
