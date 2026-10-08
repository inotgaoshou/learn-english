import SwiftUI

struct WordListDetailView: View {
    @Binding var wordList: WordList

    @State private var newWord = ""
    @State private var newPhonetic = ""
    @State private var newBritishPhonetic = ""
    @State private var newTranslation = ""
    @State private var newSentence = ""
    @State private var newSentenceTranslation = ""
    @AppStorage(SpeechAccent.storageKey) private var accentRawValue = SpeechAccent.american.rawValue
    @State private var isAddWordExpanded = false
    @State private var pendingDeleteIDs: [WordItem.ID] = []
    @State private var editingWord: WordEditDraft?
    @StateObject private var speechService = SpeechService()

    private var speechAccent: SpeechAccent {
        SpeechAccent(rawValue: accentRawValue) ?? .american
    }

    private var accentBinding: Binding<SpeechAccent> {
        Binding(
            get: { speechAccent },
            set: { accentRawValue = $0.rawValue }
        )
    }

    var body: some View {
        List {
            Section("单元") {
                TextField("名称", text: $wordList.title)
                TextField("分类", text: $wordList.category)
            }

            Section("播放与听写") {
                Picker("发音", selection: accentBinding) {
                    ForEach(SpeechAccent.allCases) { accent in
                        Text(accent.title).tag(accent)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    speakWordListInOrder()
                } label: {
                    Label("\(speechAccent.title)顺序朗读单词", systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(wordList.words.isEmpty)

                HStack(spacing: 10) {
                    Button {
                        speechService.pauseOrContinue()
                    } label: {
                        Label(speechService.isPaused ? "继续" : "暂停", systemImage: speechService.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!speechService.isSpeaking && !speechService.isPaused)

                    Button {
                        speechService.stop()
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!speechService.isSpeaking && !speechService.isPaused)
                }

                NavigationLink {
                    DictationView(wordList: wordList, mode: .ordered)
                } label: {
                    Label("按顺序听写", systemImage: "list.number")
                }
                .disabled(wordList.words.isEmpty)

                NavigationLink {
                    DictationView(wordList: wordList, mode: .shuffled)
                } label: {
                    Label("打乱听写", systemImage: "shuffle")
                }
                .disabled(wordList.words.isEmpty)
            }

            Section {
                DisclosureGroup(isExpanded: $isAddWordExpanded) {
                    addWordFields
                } label: {
                    Label("追加单词", systemImage: "plus.circle")
                        .font(.headline)
                }
            }

            Section("单词列表") {
                ForEach(wordList.words) { word in
                    HStack(spacing: 12) {
                        NavigationLink {
                            WordLearningView(words: $wordList.words, initialWordID: word.id)
                        } label: {
                            WordSummaryRow(word: word, accent: speechAccent)
                        }

                        Button {
                            speechService.speak(word.text, rate: 0.45, repetitions: 1, accent: speechAccent)
                        } label: {
                            Image(systemName: "speaker.wave.2.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .disabled(word.normalizedText.isEmpty)
                        .accessibilityLabel("播放 \(word.text) 的\(speechAccent.title)发音")

                        Menu {
                            Button {
                                editingWord = WordEditDraft(word: word)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                requestDeleteWord(id: word.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                        }
                        .buttonStyle(.borderless)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            requestDeleteWord(id: word.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            editingWord = WordEditDraft(word: word)
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
                .onDelete { offsets in
                    requestDeleteWords(at: offsets)
                }
            }
        }
        .navigationTitle(wordList.title.isEmpty ? "单元" : wordList.title)
        .sheet(item: $editingWord) { draft in
            WordEditorSheet(draft: draft) { updatedWord in
                updateWord(updatedWord)
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
            Text("删除后会从当前单元移除。")
        }
        .onDisappear {
            speechService.stop()
        }
    }

    private var addWordFields: some View {
        VStack(spacing: 12) {
            TextField("添加单词", text: $newWord)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: newWord) { _, newValue in
                    let metadata = MetadataCompletion.mergedMetadata(
                        for: newValue,
                        americanPhonetic: newPhonetic,
                        britishPhonetic: newBritishPhonetic,
                        translation: newTranslation,
                        sentence: newSentence,
                        sentenceTranslation: newSentenceTranslation
                    )
                    newPhonetic = metadata.americanPhonetic
                    newBritishPhonetic = metadata.britishPhonetic
                    newTranslation = metadata.translation
                    newSentence = metadata.sentence
                    newSentenceTranslation = metadata.sentenceTranslation
                }

            PhoneticEditorFields(
                americanPhonetic: $newPhonetic,
                britishPhonetic: $newBritishPhonetic
            )

            TextField("中文释义", text: $newTranslation)

            TextField("英文例句", text: $newSentence)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()

            TextField("例句中文", text: $newSentenceTranslation)

            MetadataCompletionRow(
                wordText: newWord,
                americanPhonetic: newPhonetic,
                britishPhonetic: newBritishPhonetic,
                translation: newTranslation,
                sentence: newSentence,
                sentenceTranslation: newSentenceTranslation,
                missingLabels: MetadataCompletion.missingLabels(
                    americanPhonetic: newPhonetic,
                    britishPhonetic: newBritishPhonetic,
                    translation: newTranslation,
                    sentence: newSentence,
                    sentenceTranslation: newSentenceTranslation
                )
            ) { metadata in
                let changed = metadata.americanPhonetic != newPhonetic
                    || metadata.britishPhonetic != newBritishPhonetic
                    || metadata.translation != newTranslation
                    || metadata.sentence != newSentence
                    || metadata.sentenceTranslation != newSentenceTranslation
                newPhonetic = metadata.americanPhonetic
                newBritishPhonetic = metadata.britishPhonetic
                newTranslation = metadata.translation
                newSentence = metadata.sentence
                newSentenceTranslation = metadata.sentenceTranslation
                return changed
            }

            Picker("发音", selection: accentBinding) {
                ForEach(SpeechAccent.allCases) { accent in
                    Text(accent.title).tag(accent)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Button {
                    speechService.speak(newWord, rate: 0.45, repetitions: 1, accent: speechAccent)
                } label: {
                    Label("\(speechAccent.title)发音", systemImage: "speaker.wave.2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(WordTextNormalizer.normalize(newWord).isEmpty)

                Button {
                    speechService.speak(newSentence, rate: 0.45, repetitions: 1, accent: speechAccent)
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
        .padding(.top, 10)
    }

    private func addNewWord() {
        let item = WordItem(text: newWord, phonetic: newPhonetic, britishPhonetic: newBritishPhonetic, translation: newTranslation, sentence: newSentence, sentenceTranslation: newSentenceTranslation)
        guard !item.normalizedText.isEmpty else {
            return
        }
        guard !wordList.words.contains(where: { $0.normalizedText == item.normalizedText }) else {
            newWord = ""
            return
        }
        wordList.words.append(item)
        newWord = ""
        newPhonetic = ""
        newBritishPhonetic = ""
        newTranslation = ""
        newSentence = ""
        newSentenceTranslation = ""
        isAddWordExpanded = false
    }

    private func speakWordListInOrder() {
        speechService.speakSequence(wordList.words.map(\.text), rate: 0.45, accent: speechAccent)
    }

    private func updateWord(_ updatedWord: WordItem) -> Bool {
        guard let index = wordList.words.firstIndex(where: { $0.id == updatedWord.id }) else {
            return false
        }
        guard !updatedWord.normalizedText.isEmpty,
              !wordList.words.contains(where: { $0.id != updatedWord.id && $0.normalizedText == updatedWord.normalizedText }) else {
            return false
        }
        wordList.words[index] = updatedWord
        return true
    }

    private func requestDeleteWord(id: WordItem.ID) {
        pendingDeleteIDs = [id]
    }

    private func requestDeleteWords(at offsets: IndexSet) {
        pendingDeleteIDs = offsets.map { wordList.words[$0].id }
    }

    private func deletePendingWords() {
        let ids = Set(pendingDeleteIDs)
        wordList.words.removeAll { ids.contains($0.id) }
        pendingDeleteIDs = []
    }
}

private struct WordSummaryRow: View {
    let word: WordItem
    let accent: SpeechAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(word.text)
                .font(.headline)
                .foregroundStyle(.primary)

            let phonetic = accent == .american ? word.phonetic : word.britishPhonetic
            if !phonetic.isEmpty {
                Text("\(accent.title) \(phonetic)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if !word.translation.isEmpty {
                Text(word.translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !word.missingMetadataLabels.isEmpty {
                Text("待补全：\(word.missingMetadataLabels.joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct WordEditDraft: Identifiable {
    let id: WordItem.ID
    var text: String
    var americanPhonetic: String
    var britishPhonetic: String
    var translation: String
    var sentence: String
    var sentenceTranslation: String

    init(word: WordItem) {
        id = word.id
        text = word.text
        americanPhonetic = word.phonetic
        britishPhonetic = word.britishPhonetic
        translation = word.translation
        sentence = word.sentence
        sentenceTranslation = word.sentenceTranslation
    }

    var wordItem: WordItem {
        WordItem(
            id: id,
            text: text,
            phonetic: americanPhonetic,
            britishPhonetic: britishPhonetic,
            translation: translation,
            sentence: sentence,
            sentenceTranslation: sentenceTranslation
        )
    }
}

private struct WordEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SpeechAccent.storageKey) private var accentRawValue = SpeechAccent.american.rawValue
    @State private var draft: WordEditDraft
    @State private var saveError: String?
    @StateObject private var speechService = SpeechService()

    let onSave: (WordItem) -> Bool

    init(draft: WordEditDraft, onSave: @escaping (WordItem) -> Bool) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("单词") {
                    TextField("英文单词或短语", text: $draft.text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    PhoneticEditorFields(
                        americanPhonetic: $draft.americanPhonetic,
                        britishPhonetic: $draft.britishPhonetic
                    )

                    TextField("中文释义", text: $draft.translation)
                    TextField("英文例句", text: $draft.sentence)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()

                    TextField("例句中文", text: $draft.sentenceTranslation)
                }

                Section("补全与试听") {
                    MetadataCompletionRow(
                        wordText: draft.text,
                        americanPhonetic: draft.americanPhonetic,
                        britishPhonetic: draft.britishPhonetic,
                        translation: draft.translation,
                        sentence: draft.sentence,
                        sentenceTranslation: draft.sentenceTranslation,
                        missingLabels: MetadataCompletion.missingLabels(
                            americanPhonetic: draft.americanPhonetic,
                            britishPhonetic: draft.britishPhonetic,
                            translation: draft.translation,
                            sentence: draft.sentence,
                            sentenceTranslation: draft.sentenceTranslation
                        )
                    ) { metadata in
                        let changed = metadata.americanPhonetic != draft.americanPhonetic
                            || metadata.britishPhonetic != draft.britishPhonetic
                            || metadata.translation != draft.translation
                            || metadata.sentence != draft.sentence
                            || metadata.sentenceTranslation != draft.sentenceTranslation
                        draft.americanPhonetic = metadata.americanPhonetic
                        draft.britishPhonetic = metadata.britishPhonetic
                        draft.translation = metadata.translation
                        draft.sentence = metadata.sentence
                        draft.sentenceTranslation = metadata.sentenceTranslation
                        return changed
                    }

                    Button {
                        speechService.speak(draft.text, rate: 0.45, repetitions: 1, accent: accent)
                    } label: {
                        Label("播放\(accent.title)发音", systemImage: "speaker.wave.2")
                    }
                    .disabled(WordTextNormalizer.normalize(draft.text).isEmpty)

                    Button {
                        speechService.speak(draft.sentence, rate: 0.42, repetitions: 1, accent: accent)
                    } label: {
                        Label("播放例句", systemImage: "quote.bubble")
                    }
                    .disabled(WordTextNormalizer.normalize(draft.sentence).isEmpty)
                }
            }
            .navigationTitle("编辑单词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if onSave(draft.wordItem) {
                            dismiss()
                        } else {
                            saveError = "单词不能为空，也不能与当前单元中的其他单词重复。"
                        }
                    }
                    .disabled(WordTextNormalizer.normalize(draft.text).isEmpty)
                }
            }
        }
        .onDisappear {
            speechService.stop()
        }
        .alert("无法保存", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private var accent: SpeechAccent {
        SpeechAccent(rawValue: accentRawValue) ?? .american
    }
}
