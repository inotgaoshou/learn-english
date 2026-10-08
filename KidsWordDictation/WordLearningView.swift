import SwiftUI
import Translation

struct WordLearningView: View {
    @Binding var words: [WordItem]

    @AppStorage(SpeechAccent.storageKey) private var accentRawValue = SpeechAccent.american.rawValue
    @State private var currentIndex: Int
    @State private var stage: LearningStage = .learn
    @State private var readingMode: ReadingMode = .syllables
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
            wordNavigator
            stageProgress

            ScrollView {
                VStack(spacing: 14) {
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
                .padding(.top, 12)
                .padding(.bottom, 104)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .tint(LearningPalette.primary)
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
                Text("当前单词")
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

    private var wordNavigator: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                        Button {
                            move(to: index)
                        } label: {
                            Text(word.text)
                                .font(.subheadline.weight(index == currentIndex ? .bold : .medium))
                                .foregroundStyle(index == currentIndex ? LearningPalette.primary : .primary)
                                .lineLimit(1)
                                .padding(.horizontal, 11)
                                .frame(height: 36)
                                .background(
                                    index == currentIndex ? LearningPalette.primary.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                        }
                        .buttonStyle(.plain)
                        .id(word.id)
                        .accessibilityLabel("学习 \(word.text)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .dynamicTypeSize(.small ... .xxxLarge)
            .onAppear {
                proxy.scrollTo(currentWord.id, anchor: .center)
            }
            .onChange(of: currentIndex) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(currentWord.id, anchor: .center)
                }
            }
        }
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
                                .foregroundStyle(stageForeground(for: item))
                        }
                        Text(item.title)
                            .font(.caption.weight(stage == item ? .bold : .medium))
                            .foregroundStyle(.white)
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
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(LearningPalette.primary)
        .dynamicTypeSize(.small ... .xxxLarge)
    }

    private var learnView: some View {
        VStack(spacing: 18) {
            wordHero

            if let guide {
                VStack(alignment: .leading, spacing: 10) {
                    Label("音节拆分", systemImage: "rectangle.split.3x1")
                        .font(.headline)
                    syllableGrid(guide)
                }
            }

            exampleSection

            if !currentWord.missingMetadataLabels.isEmpty {
                Label("待补全：\(currentWord.missingMetadataLabels.joined(separator: "、"))", systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .learningSurface()
    }

    private var readView: some View {
        VStack(spacing: 18) {
            wordHero

            if let guide {
                Picker("拼读方式", selection: $readingMode) {
                    ForEach(ReadingMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 10) {
                    Text(readingMode.title)
                        .font(.headline)

                    if readingMode == .syllables {
                        syllableGrid(guide)
                    } else {
                        pronunciationUnitGrid(guide)
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

                exampleSection
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
            wordHero

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

    private var wordHero: some View {
        VStack(spacing: 10) {
            segmentedWord
            phoneticLine

            if !currentWord.translation.isEmpty {
                Text(currentWord.translation)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func syllableGrid(_ guide: PronunciationGuide) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 10)], spacing: 10) {
            ForEach(Array(guide.syllables.enumerated()), id: \.element.id) { index, syllable in
                Button {
                    speakSyllable(syllable)
                } label: {
                    VStack(spacing: 4) {
                        Text(syllable.text)
                            .font(.title3.bold())
                        Text("/\(ipa(for: syllable))/")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(LearningTileButtonStyle(tint: syllableColor(index)))
                .accessibilityLabel("播放音节 \(syllable.text)")
            }
        }
    }

    private func pronunciationUnitGrid(_ guide: PronunciationGuide) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 9)], spacing: 9) {
            ForEach(Array(guide.units.enumerated()), id: \.element.id) { index, unit in
                Button {
                    speechService.speakIPA(ipa(for: unit), accent: accent)
                } label: {
                    VStack(spacing: 3) {
                        Text(unit.letters)
                            .font(.title2.bold())
                        Text("/\(ipa(for: unit))/")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Image(systemName: "play.fill")
                            .font(.caption2)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                }
                .buttonStyle(LearningTileButtonStyle(
                    tint: speechService.activeSequenceIndex == index ? .green : LearningPalette.secondary,
                    isHighlighted: speechService.activeSequenceIndex == index
                ))
                .accessibilityLabel("播放拼读块 \(unit.letters)")
            }
        }
    }

    @ViewBuilder
    private var exampleSection: some View {
        if !currentWord.sentence.isEmpty {
            Divider()

            VStack(spacing: 9) {
                Text(currentWord.sentence)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

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

                HStack(spacing: 10) {
                    Button {
                        speakExample(rate: 0.38)
                    } label: {
                        Label("标准语速", systemImage: "speaker.wave.2.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        speakExample(rate: 0.29)
                    } label: {
                        Label("慢速", systemImage: "tortoise.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
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
        .font(.system(size: 52, weight: .bold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.36)
        .frame(maxWidth: .infinity, minHeight: 66)
        .accessibilityLabel(currentWord.text)
    }

    private var phoneticLine: some View {
        HStack(spacing: 8) {
            Text(accent.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LearningPalette.primary)
            Text(selectedPhonetic.isEmpty ? "暂无音标" : selectedPhonetic)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            compactSpeakerButton(label: "播放单词") {
                speakCurrent(rate: 0.43)
                if stage == .learn {
                    markComplete(.learn)
                }
            }
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
        HStack(spacing: 10) {
            Button {
                move(by: -1)
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "backward.end.fill")
                    Text("上一词")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
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
                VStack(spacing: 3) {
                    Image(systemName: "speaker.wave.2.fill")
                    Text("重听")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)

            Button {
                move(by: 1)
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "forward.end.fill")
                    Text("下一词")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
            .disabled(currentIndex >= words.count - 1)
            .accessibilityLabel("下一个单词")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
        .tint(LearningPalette.primary)
    }

    private func compactSpeakerButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.title3)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(LearningPalette.primary)
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

    private func speakExample(rate: Float) {
        speechService.speak(currentWord.sentence, rate: rate, repetitions: 1, accent: accent)
        if stage == .learn {
            markComplete(.learn)
        }
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
        move(to: currentIndex + offset)
    }

    private func move(to target: Int) {
        guard words.indices.contains(target), target != currentIndex else {
            return
        }
        speechService.stop()
        currentIndex = target
    }

    private func resetForCurrentWord() {
        puzzle = Self.makePuzzle(for: currentWord)
        hasCheckedPuzzle = false
        readingMode = .syllables
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
        stage == item || completedForCurrentWord.contains(item)
            ? .white
            : .white.opacity(0.18)
    }

    private func stageForeground(for item: LearningStage) -> Color {
        stage == item || completedForCurrentWord.contains(item)
            ? LearningPalette.primary
            : .white.opacity(0.8)
    }

    private func connectorColor(after item: LearningStage) -> Color {
        completedForCurrentWord.contains(item) ? .white : .white.opacity(0.24)
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

private enum ReadingMode: String, CaseIterable, Identifiable {
    case syllables
    case phonics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .syllables: return "音节拆分"
        case .phonics: return "自然拼读"
        }
    }

    var systemImage: String {
        switch self {
        case .syllables: return "rectangle.split.3x1"
        case .phonics: return "character.book.closed.fill"
        }
    }
}

enum LearningPalette {
    static let primary = Color(red: 0.04, green: 0.43, blue: 0.96)
    static let secondary = Color(red: 0.93, green: 0.48, blue: 0.08)
    static let word = Color(red: 0.90, green: 0.45, blue: 0.05)
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
