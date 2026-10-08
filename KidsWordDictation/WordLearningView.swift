import SwiftUI
import Translation

struct WordLearningView: View {
    @Binding var words: [WordItem]

    @AppStorage(SpeechAccent.storageKey) private var accentRawValue = SpeechAccent.american.rawValue
    @State private var currentIndex: Int
    @State private var stage: LearningStage = .learn
    @State private var puzzle: SpellingPuzzle
    @State private var hasCheckedPuzzle = false
    @State private var learningProgress = LearningProgress()
    @State private var pendingTranslationWordID: WordItem.ID?
    @State private var pendingTranslationSentence = ""
    @State private var sentenceTranslationMessage = ""
    @State private var sentenceTranslationConfiguration: TranslationSession.Configuration?
    @StateObject private var speechService = SpeechService()

    init(words: Binding<[WordItem]>, initialWordID: WordItem.ID) {
        _words = words
        let values = words.wrappedValue
        let index = values.firstIndex(where: { $0.id == initialWordID }) ?? 0
        _currentIndex = State(initialValue: index)
        let initialWord = values.indices.contains(index) ? values[index] : WordItem(text: "")
        _puzzle = State(initialValue: Self.makePuzzle(for: initialWord))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 18) {
                    stageProgress

                    switch stage {
                    case .learn:
                        learnView
                    case .read:
                        readView
                    case .spell:
                        spellingView
                    }
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 104)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("单词学习")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            bottomControls
        }
        .translationTask(sentenceTranslationConfiguration) { session in
            await translatePendingSentence(using: session)
        }
        .onAppear {
            speakCurrent(rate: 0.43)
            requestSentenceTranslationIfNeeded()
        }
        .onDisappear {
            speechService.stop()
        }
        .onChange(of: currentIndex) { _, _ in
            resetForCurrentWord()
            speakCurrent(rate: 0.43)
            requestSentenceTranslationIfNeeded()
        }
    }

    private var currentWord: WordItem {
        guard words.indices.contains(currentIndex) else {
            return WordItem(text: "")
        }
        return words[currentIndex]
    }

    private var guide: PronunciationGuide? {
        PronunciationGuideProvider.guide(for: currentWord.text)
    }

    private var accent: SpeechAccent {
        SpeechAccent(rawValue: accentRawValue) ?? .american
    }

    private var accentBinding: Binding<SpeechAccent> {
        Binding(
            get: { accent },
            set: { newAccent in
                speechService.stop()
                accentRawValue = newAccent.rawValue
            }
        )
    }

    private var selectedPhonetic: String {
        accent == .american ? currentWord.phonetic : currentWord.britishPhonetic
    }

    private var completedForCurrentWord: Set<LearningStage> {
        learningProgress.completedStages(for: currentWord.id)
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("第 \(min(currentIndex + 1, words.count)) / \(words.count) 个")
                    .font(.headline.monospacedDigit())
                Text("完成学、读、拼三个阶段")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Picker("发音", selection: accentBinding) {
                ForEach(SpeechAccent.allCases) { accent in
                    Text(accent.title).tag(accent)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 136)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var stageProgress: some View {
        HStack(spacing: 0) {
            ForEach(Array(LearningStage.allCases.enumerated()), id: \.element.id) { index, item in
                Button {
                    speechService.stop()
                    stage = item
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(stageColor(for: item))
                                .frame(width: 38, height: 38)
                            Image(systemName: completedForCurrentWord.contains(item) ? "checkmark" : item.systemImage)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(stage == item || completedForCurrentWord.contains(item) ? .white : .secondary)
                        }
                        Text(item.title)
                            .font(.caption.weight(stage == item ? .bold : .medium))
                            .foregroundStyle(stage == item ? Color.accentColor : .secondary)
                    }
                    .frame(width: 58)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.title)阶段")

                if index < LearningStage.allCases.count - 1 {
                    Capsule()
                        .fill(connectorColor(after: item))
                        .frame(maxWidth: .infinity, minHeight: 4, maxHeight: 4)
                        .padding(.horizontal, 4)
                        .offset(y: -10)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var learnView: some View {
        VStack(spacing: 20) {
            HStack(alignment: .center, spacing: 10) {
                segmentedWord
                compactSpeakerButton(label: "播放单词") {
                    speakCurrent(rate: 0.43)
                    markComplete(.learn)
                }
            }

            phoneticLine

            if !currentWord.translation.isEmpty {
                Text(currentWord.translation)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if !currentWord.sentence.isEmpty {
                Divider()
                VStack(spacing: 9) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(currentWord.sentence)
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        compactSpeakerButton(label: "播放例句") {
                            speechService.speak(currentWord.sentence, rate: 0.38, repetitions: 1, accent: accent)
                            markComplete(.learn)
                        }
                    }

                    if !currentWord.sentenceTranslation.isEmpty {
                        Text(currentWord.sentenceTranslation)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Button {
                            requestSentenceTranslationIfNeeded(force: true)
                        } label: {
                            Label(
                                sentenceTranslationMessage.isEmpty ? "补全例句中文" : sentenceTranslationMessage,
                                systemImage: "translate"
                            )
                            .font(.callout)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if !currentWord.missingMetadataLabels.isEmpty {
                Label("待补全：\(currentWord.missingMetadataLabels.joined(separator: "、"))", systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .learningSurface()
    }

    private var readView: some View {
        VStack(spacing: 20) {
            HStack(spacing: 10) {
                segmentedWord
                compactSpeakerButton(label: "播放单词") {
                    speakCurrent(rate: 0.43)
                }
            }
            phoneticLine

            if let guide {
                VStack(alignment: .leading, spacing: 10) {
                    Text("音节")
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 10)], spacing: 10) {
                        ForEach(Array(guide.syllables.enumerated()), id: \.element.id) { index, syllable in
                            Button {
                                speakSyllable(syllable)
                            } label: {
                                VStack(spacing: 4) {
                                    Text(syllable.text)
                                        .font(.title3.bold())
                                    Text("/\(ipa(for: syllable))/")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity, minHeight: 58)
                            }
                            .buttonStyle(LearningTileButtonStyle(tint: syllableColor(index)))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("拼读块")
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 9)], spacing: 9) {
                        ForEach(Array(guide.units.enumerated()), id: \.element.id) { index, unit in
                            Button {
                                speechService.speakIPA(ipa(for: unit), accent: accent)
                            } label: {
                                VStack(spacing: 4) {
                                    Text(unit.letters)
                                        .font(.title2.bold())
                                    Text("/\(ipa(for: unit))/")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.65)
                                }
                                .frame(maxWidth: .infinity, minHeight: 62)
                            }
                            .buttonStyle(LearningTileButtonStyle(
                                tint: speechService.activeSequenceIndex == index ? .green : .accentColor,
                                isHighlighted: speechService.activeSequenceIndex == index
                            ))
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        playSegments(guide)
                    } label: {
                        Label("逐段播放", systemImage: "text.line.first.and.arrowtriangle.forward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        speakCurrent(rate: 0.31)
                    } label: {
                        Label("慢速整词", systemImage: "tortoise.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ContentUnavailableView(
                    "暂无可靠拼读拆分",
                    systemImage: "text.badge.xmark",
                    description: Text("为避免教错，当前只提供整词发音；拼写练习仍可使用。")
                )

                Button {
                    speakCurrent(rate: 0.40)
                } label: {
                    Label("播放整词", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .learningSurface()
    }

    private var spellingView: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                compactSpeakerButton(label: "播放当前单词") {
                    speakCurrent(rate: 0.40)
                }
                if !currentWord.translation.isEmpty {
                    Text(currentWord.translation)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }

            phoneticLine

            VStack(alignment: .leading, spacing: 10) {
                Text("你的答案")
                    .font(.headline)
                spellingSlots
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("点击拼写块")
                    .font(.headline)
                spellingChoices
            }

            if hasCheckedPuzzle {
                Label(
                    puzzle.isCorrect ? "拼写正确" : "顺序不对，请撤回或重置后再试",
                    systemImage: puzzle.isCorrect ? "checkmark.circle.fill" : "arrow.counterclockwise.circle.fill"
                )
                .font(.headline)
                .foregroundStyle(puzzle.isCorrect ? .green : .orange)
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 12) {
                Button {
                    puzzle.undoLastSelection()
                    hasCheckedPuzzle = false
                } label: {
                    Label("撤回", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(puzzle.selectedPieces.isEmpty)

                Button {
                    puzzle.reset()
                    hasCheckedPuzzle = false
                } label: {
                    Label("重置", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(puzzle.selectedPieces.isEmpty)
            }
        }
        .learningSurface()
    }

    private var segmentedWord: some View {
        Group {
            if let guide {
                guide.syllables.enumerated().reduce(Text("")) { result, item in
                    result + Text(item.element.text).foregroundStyle(syllableColor(item.offset))
                }
            } else {
                Text(currentWord.text)
                    .foregroundStyle(.primary)
            }
        }
        .font(.system(size: 44, weight: .bold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.42)
        .frame(maxWidth: .infinity, minHeight: 58)
        .accessibilityLabel(currentWord.text)
    }

    private var phoneticLine: some View {
        HStack(spacing: 6) {
            Text(accent.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(selectedPhonetic.isEmpty ? "暂无音标" : selectedPhonetic)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }

    private var spellingSlots: some View {
        let pieceCount = puzzle.availablePieces.count + puzzle.selectedPieces.count
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 52, maximum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(0..<pieceCount, id: \.self) { index in
                Group {
                    if puzzle.selectedPieces.indices.contains(index) {
                        Text(puzzle.selectedPieces[index].text)
                            .foregroundStyle(hasCheckedPuzzle && puzzle.isCorrect ? .green : Color.accentColor)
                    } else {
                        Text(" ")
                            .accessibilityHidden(true)
                    }
                }
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 5)
                .background(slotBackground(index: index), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(slotBorder(index: index), lineWidth: 1.5)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }

    private var spellingChoices: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52, maximum: 88), spacing: 9)], alignment: .leading, spacing: 9) {
            ForEach(puzzle.availablePieces) { piece in
                Button {
                    selectSpellingPiece(piece.id)
                } label: {
                    Text(piece.text)
                        .font(.title3.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(LearningTileButtonStyle(tint: .accentColor))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    }

    private var bottomControls: some View {
        HStack(spacing: 12) {
            Button {
                move(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .disabled(currentIndex == 0)
            .accessibilityLabel("上一个单词")

            Button {
                speakCurrent(rate: 0.43)
                if stage == .learn {
                    markComplete(.learn)
                }
            } label: {
                Label("重听", systemImage: "speaker.wave.2.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)

            Button {
                move(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .disabled(currentIndex >= words.count - 1)
            .accessibilityLabel("下一个单词")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.bar)
    }

    private func compactSpeakerButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.title3)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }

    private func ipa(for unit: PronunciationUnit) -> String {
        accent == .american ? unit.americanIPA : unit.britishIPA
    }

    private func ipa(for syllable: PronunciationSyllable) -> String {
        syllable.units.map(ipa(for:)).joined()
    }

    private func speakSyllable(_ syllable: PronunciationSyllable) {
        speechService.speakIPA(ipa(for: syllable), accent: accent)
    }

    private func playSegments(_ guide: PronunciationGuide) {
        let wordID = currentWord.id
        speechService.speakIPASequence(guide.units.map(ipa(for:)), accent: accent) {
            learningProgress.markComplete(.read, for: wordID)
        }
    }

    private func speakCurrent(rate: Float) {
        speechService.speak(currentWord.text, rate: rate, repetitions: 1, accent: accent)
    }

    private func selectSpellingPiece(_ id: SpellingPiece.ID) {
        guard !puzzle.isComplete else {
            return
        }
        puzzle.select(pieceID: id)
        guard puzzle.isComplete else {
            hasCheckedPuzzle = false
            return
        }

        hasCheckedPuzzle = true
        if puzzle.isCorrect {
            markComplete(.spell)
            speakCurrent(rate: 0.43)
        }
    }

    private func move(by offset: Int) {
        let target = currentIndex + offset
        guard words.indices.contains(target) else {
            return
        }
        speechService.stop()
        currentIndex = target
    }

    private func resetForCurrentWord() {
        puzzle = Self.makePuzzle(for: currentWord)
        hasCheckedPuzzle = false
        sentenceTranslationMessage = ""
    }

    private static func makePuzzle(for word: WordItem) -> SpellingPuzzle {
        let pieces = PronunciationGuideProvider.guide(for: word.text)?.spellingPieces ?? []
        return SpellingPuzzle(answer: word.text, preferredChunks: pieces)
    }

    private func markComplete(_ item: LearningStage) {
        learningProgress.markComplete(item, for: currentWord.id)
    }

    private func stageColor(for item: LearningStage) -> Color {
        if completedForCurrentWord.contains(item) {
            return .green
        }
        return stage == item ? .accentColor : Color(.tertiarySystemFill)
    }

    private func connectorColor(after item: LearningStage) -> Color {
        completedForCurrentWord.contains(item) ? .green.opacity(0.7) : Color(.tertiarySystemFill)
    }

    private func slotBackground(index: Int) -> Color {
        if hasCheckedPuzzle && puzzle.isCorrect && puzzle.selectedPieces.indices.contains(index) {
            return .green.opacity(0.12)
        }
        return Color(.tertiarySystemGroupedBackground)
    }

    private func slotBorder(index: Int) -> Color {
        if hasCheckedPuzzle && puzzle.isCorrect && puzzle.selectedPieces.indices.contains(index) {
            return .green.opacity(0.7)
        }
        return Color.secondary.opacity(0.25)
    }

    private func requestSentenceTranslationIfNeeded(force: Bool = false) {
        guard !currentWord.sentence.isEmpty,
              currentWord.sentenceTranslation.isEmpty,
              force || pendingTranslationWordID != currentWord.id else {
            return
        }

        pendingTranslationWordID = currentWord.id
        pendingTranslationSentence = currentWord.sentence
        sentenceTranslationMessage = "正在翻译例句"
        sentenceTranslationConfiguration = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "zh-Hans")
        )
        sentenceTranslationConfiguration?.invalidate()
    }

    @MainActor
    private func translatePendingSentence(using session: TranslationSession) async {
        guard let wordID = pendingTranslationWordID,
              !pendingTranslationSentence.isEmpty else {
            return
        }
        let sourceSentence = pendingTranslationSentence

        do {
            try await session.prepareTranslation()
            let response = try await session.translate(sourceSentence)
            guard let index = words.firstIndex(where: { $0.id == wordID }),
                  words[index].sentence == sourceSentence else {
                return
            }
            words[index].sentenceTranslation = WordTextNormalizer.displayText(for: response.targetText)
            if currentWord.id == wordID {
                sentenceTranslationMessage = ""
            }
        } catch {
            if currentWord.id == wordID {
                sentenceTranslationMessage = "例句翻译暂不可用，点击重试"
            }
        }

        if pendingTranslationWordID == wordID, pendingTranslationSentence == sourceSentence {
            pendingTranslationWordID = nil
            pendingTranslationSentence = ""
        }
    }

    private func syllableColor(_ index: Int) -> Color {
        let colors: [Color] = [.green, .orange, .blue, .pink, .teal]
        return colors[index % colors.count]
    }
}

private extension LearningStage {
    var title: String {
        switch self {
        case .learn: return "学"
        case .read: return "读"
        case .spell: return "拼"
        }
    }

    var systemImage: String {
        switch self {
        case .learn: return "book.fill"
        case .read: return "speaker.wave.2.fill"
        case .spell: return "puzzlepiece.fill"
        }
    }
}

private extension View {
    func learningSurface() -> some View {
        padding(18)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LearningTileButtonStyle: ButtonStyle {
    let tint: Color
    var isHighlighted = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .background(
                tint.opacity(isHighlighted ? 0.20 : (configuration.isPressed ? 0.16 : 0.09)),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(tint.opacity(isHighlighted ? 0.65 : 0.28), lineWidth: isHighlighted ? 2 : 1)
            }
    }
}
