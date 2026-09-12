import SwiftUI

struct WordListDetailView: View {
    @Binding var wordList: WordList

    @State private var newWord = ""
    @State private var newPhonetic = ""
    @State private var newBritishPhonetic = ""
    @State private var newTranslation = ""
    @State private var newSentence = ""
    @State private var newWordAccent: SpeechAccent = .american
    @State private var pendingDeleteIDs: [WordItem.ID] = []
    @StateObject private var speechService = SpeechService()

    var body: some View {
        List {
            Section("单元") {
                TextField("名称", text: $wordList.title)
                TextField("分类", text: $wordList.category)
            }

            Section {
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

            Section("追加单词") {
                TextField("添加单词", text: $newWord)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: newWord) { _, newValue in
                        if newPhonetic.isEmpty {
                            newPhonetic = WordPhoneticLookup.phonetic(for: newValue)
                        }
                        if newBritishPhonetic.isEmpty {
                            newBritishPhonetic = WordPhoneticLookup.britishPhonetic(for: newValue)
                        }
                        if newTranslation.isEmpty {
                            newTranslation = WordTranslationLookup.translation(for: newValue)
                        }
                    }

                PhoneticEditorFields(
                    americanPhonetic: $newPhonetic,
                    britishPhonetic: $newBritishPhonetic
                )

                TextField("中文释义", text: $newTranslation)

                TextField("英文例句", text: $newSentence)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()

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
                                        if word.phonetic.isEmpty {
                                            word.phonetic = WordPhoneticLookup.phonetic(for: newValue)
                                        }
                                        if word.britishPhonetic.isEmpty {
                                            word.britishPhonetic = WordPhoneticLookup.britishPhonetic(for: newValue)
                                        }
                                        if word.translation.isEmpty {
                                            word.translation = WordTranslationLookup.translation(for: newValue)
                                        }
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
                        }

                        Menu {
                            Button {
                                speechService.speak(word.text, rate: 0.45, repetitions: 1, accent: .american)
                            } label: {
                                Label("美式发音", systemImage: "speaker.wave.2")
                            }

                            Button {
                                speechService.speak(word.text, rate: 0.45, repetitions: 1, accent: .british)
                            } label: {
                                Label("英式发音", systemImage: "speaker.wave.2")
                            }
                        } label: {
                            Image(systemName: "speaker.wave.2.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(word.normalizedText.isEmpty)
                        .accessibilityLabel("选择 \(word.text) 的发音")

                        Button {
                            speechService.speak(word.sentence, rate: 0.45, repetitions: 1)
                        } label: {
                            Image(systemName: "quote.bubble")
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
