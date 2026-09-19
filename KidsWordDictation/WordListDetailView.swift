import SwiftUI

struct WordListDetailView: View {
    @Binding var wordList: WordList

    @State private var newWord = ""
    @State private var newPhonetic = ""
    @State private var newBritishPhonetic = ""
    @State private var newTranslation = ""
    @State private var newSentence = ""
    @State private var newWordAccent: SpeechAccent = .american
    @State private var isAddWordExpanded = false
    @State private var pendingDeleteIDs: [WordItem.ID] = []
    @StateObject private var speechService = SpeechService()

    var body: some View {
        List {
            Section("单元") {
                TextField("名称", text: $wordList.title)
                TextField("分类", text: $wordList.category)
            }

            Section("播放与听写") {
                Picker("发音", selection: $newWordAccent) {
                    ForEach(SpeechAccent.allCases) { accent in
                        Text(accent.title).tag(accent)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    speakWordListInOrder()
                } label: {
                    Label("\(newWordAccent.title)顺序朗读单词", systemImage: "play.circle")
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
                ForEach($wordList.words) { $word in
                    HStack(spacing: 12) {
                        VStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("word", text: $word.text)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .onChange(of: word.text) { _, newValue in
                                        word.normalizedText = WordTextNormalizer.normalize(newValue)
                                        let metadata = MetadataCompletion.mergedMetadata(
                                            for: newValue,
                                            americanPhonetic: word.phonetic,
                                            britishPhonetic: word.britishPhonetic,
                                            translation: word.translation,
                                            sentence: word.sentence
                                        )
                                        word.phonetic = metadata.americanPhonetic
                                        word.britishPhonetic = metadata.britishPhonetic
                                        word.translation = metadata.translation
                                        word.sentence = metadata.sentence
                                    }

                            }

                            PhoneticEditorFields(
                                americanPhonetic: $word.phonetic,
                                britishPhonetic: $word.britishPhonetic,
                                americanPlaceholder: "美式音标",
                                britishPlaceholder: "英式音标"
                            )

                            TextField("中文释义", text: $word.translation)

                            TextField("英文例句", text: $word.sentence)
                                .textInputAutocapitalization(.sentences)
                                .autocorrectionDisabled()

                            MetadataCompletionRow(
                                missingLabels: MetadataCompletion.missingLabels(
                                    americanPhonetic: word.phonetic,
                                    britishPhonetic: word.britishPhonetic,
                                    translation: word.translation
                                )
                            ) {
                                let metadata = MetadataCompletion.mergedMetadata(
                                    for: word.text,
                                    americanPhonetic: word.phonetic,
                                    britishPhonetic: word.britishPhonetic,
                                    translation: word.translation,
                                    sentence: word.sentence
                                )
                                word.phonetic = metadata.americanPhonetic
                                word.britishPhonetic = metadata.britishPhonetic
                                word.translation = metadata.translation
                                word.sentence = metadata.sentence
                            }
                        }

                        Button {
                            speechService.speak(word.text, rate: 0.45, repetitions: 1, accent: newWordAccent)
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "speaker.wave.2.circle")
                                Text("发音")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(word.normalizedText.isEmpty)
                        .accessibilityLabel("播放 \(word.text) 的\(newWordAccent.title)发音")

                        Button {
                            speechService.speak(word.sentence, rate: 0.45, repetitions: 1, accent: newWordAccent)
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "quote.bubble")
                                Text("例句")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(WordTextNormalizer.normalize(word.sentence).isEmpty)
                        .accessibilityLabel("播放 \(word.text) 的例句")

                        Button(role: .destructive) {
                            requestDeleteWord(id: word.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("删除 \(word.text)")
                    }
                }
                .onDelete { offsets in
                    requestDeleteWords(at: offsets)
                }
            }
        }
        .navigationTitle(wordList.title.isEmpty ? "单元" : wordList.title)
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
                newPhonetic = metadata.americanPhonetic
                newBritishPhonetic = metadata.britishPhonetic
                newTranslation = metadata.translation
                newSentence = metadata.sentence
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
        .padding(.top, 10)
    }

    private func addNewWord() {
        let item = WordItem(text: newWord, phonetic: newPhonetic, britishPhonetic: newBritishPhonetic, translation: newTranslation, sentence: newSentence)
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
        isAddWordExpanded = false
    }

    private func speakWordListInOrder() {
        speechService.speakSequence(wordList.words.map(\.text), rate: 0.45, accent: newWordAccent)
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
