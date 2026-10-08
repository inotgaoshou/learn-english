import SwiftUI

struct WordLearningView: View {
    let words: [WordItem]

    @AppStorage(SpeechAccent.storageKey) private var accentRawValue = SpeechAccent.american.rawValue
    @State private var currentIndex: Int
    @State private var stage: LearningStage = .learn
    @State private var puzzle: SpellingPuzzle
    @State private var hasCheckedPuzzle = false
    @StateObject private var speechService = SpeechService()

    init(words: [WordItem], initialWordID: WordItem.ID) {
        self.words = words
        let index = words.firstIndex(where: { $0.id == initialWordID }) ?? 0
        _currentIndex = State(initialValue: index)
        let initialWord = words.indices.contains(index) ? words[index] : WordItem(text: "")
        let chunks = PronunciationGuideProvider.guide(for: initialWord.text)?.spellingChunks ?? []
        _puzzle = State(initialValue: SpellingPuzzle(answer: initialWord.text, preferredChunks: chunks))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 22) {
                    stagePicker

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
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 110)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("单词学习")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            bottomControls
        }
        .onAppear {
            speakCurrent(rate: 0.43)
        }
        .onDisappear {
            speechService.stop()
        }
        .onChange(of: currentIndex) { _, _ in
            resetForCurrentWord()
            speakCurrent(rate: 0.43)
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
            set: { accentRawValue = $0.rawValue }
        )
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("第 \(min(currentIndex + 1, words.count)) / \(words.count) 个")
                    .font(.headline.monospacedDigit())
                Text("点击音节和音素即可点读")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("发音", selection: accentBinding) {
                ForEach(SpeechAccent.allCases) { accent in
                    Text(accent.title).tag(accent)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 132)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var stagePicker: some View {
        Picker("学习阶段", selection: $stage) {
            ForEach(LearningStage.allCases) { stage in
                Label(stage.title, systemImage: stage.systemImage)
                    .tag(stage)
            }
        }
        .pickerStyle(.segmented)
    }

    private var learnView: some View {
        VStack(spacing: 24) {
            segmentedWord

            Button {
                speakCurrent(rate: 0.43)
            } label: {
                Label("\(accent.title)发音", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(.borderedProminent)

            phoneticBlock

            if !currentWord.translation.isEmpty {
                Text(currentWord.translation)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if !currentWord.sentence.isEmpty {
                Divider()
                VStack(spacing: 12) {
                    Text(currentWord.sentence)
                        .font(.title3)
                        .multilineTextAlignment(.center)

                    Button {
                        speechService.speak(currentWord.sentence, rate: 0.40, repetitions: 1, accent: accent)
                    } label: {
                        Label("朗读例句", systemImage: "quote.bubble.fill")
                    }
                    .buttonStyle(.bordered)
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
        VStack(spacing: 22) {
            segmentedWord
            phoneticBlock

            if let guide {
                VStack(alignment: .leading, spacing: 12) {
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

                VStack(alignment: .leading, spacing: 12) {
                    Text("拼读块")
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 10)], spacing: 10) {
                        ForEach(Array(guide.units.enumerated()), id: \.element.id) { index, unit in
                            Button {
                                speechService.speakIPA(ipa(for: unit), accent: accent)
                            } label: {
                                VStack(spacing: 5) {
                                    Text(unit.letters)
                                        .font(.title2.bold())
                                    Text("/\(ipa(for: unit))/")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.65)
                                }
                                .frame(maxWidth: .infinity, minHeight: 64)
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
                        speakCurrent(rate: 0.32)
                    } label: {
                        Label("慢速整词", systemImage: "tortoise.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    speakCurrent(rate: 0.45)
                } label: {
                    Label("正常整词", systemImage: "speaker.wave.2.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
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
        VStack(spacing: 22) {
            Button {
                speakCurrent(rate: 0.40)
            } label: {
                Image(systemName: "speaker.wave.2.circle.fill")
                    .font(.system(size: 58))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放当前单词")

            if !currentWord.translation.isEmpty {
                Text(currentWord.translation)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

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
                    puzzle.isCorrect ? "拼写正确" : "顺序不对，再试一次",
                    systemImage: puzzle.isCorrect ? "checkmark.circle.fill" : "arrow.counterclockwise.circle.fill"
                )
                .font(.headline)
                .foregroundStyle(puzzle.isCorrect ? .green : .orange)
            }

            HStack(spacing: 10) {
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

                Button {
                    hasCheckedPuzzle = true
                    if puzzle.isCorrect {
                        speakCurrent(rate: 0.43)
                    }
                } label: {
                    Label("检查", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!puzzle.isComplete)
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
        .font(.system(size: 46, weight: .bold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.48)
        .frame(maxWidth: .infinity, minHeight: 62)
        .accessibilityLabel(currentWord.text)
    }

    private var phoneticBlock: some View {
        VStack(spacing: 6) {
            if !currentWord.phonetic.isEmpty {
                Text("美  \(currentWord.phonetic)")
            }
            if !currentWord.britishPhonetic.isEmpty && currentWord.britishPhonetic != currentWord.phonetic {
                Text("英  \(currentWord.britishPhonetic)")
            } else if !currentWord.britishPhonetic.isEmpty {
                Text("英  \(currentWord.britishPhonetic)")
            }
        }
        .font(.body.monospaced())
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }

    private var spellingSlots: some View {
        Group {
            if puzzle.selectedPieces.isEmpty {
                Text("从下方选择拼写块")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(puzzle.selectedPieces) { piece in
                    Text(piece.text)
                        .font(.title3.bold())
                        .frame(minWidth: 50, minHeight: 46)
                        .padding(.horizontal, 6)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                }
                }
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            }
        }
    }

    private var spellingChoices: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 9)], alignment: .leading, spacing: 9) {
            ForEach(puzzle.availablePieces) { piece in
                Button {
                    puzzle.select(pieceID: piece.id)
                    hasCheckedPuzzle = false
                } label: {
                    Text(piece.text)
                        .font(.title3.bold())
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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
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
        speechService.speakIPASequence(guide.units.map(ipa(for:)), accent: accent)
    }

    private func speakCurrent(rate: Float) {
        speechService.speak(currentWord.text, rate: rate, repetitions: 1, accent: accent)
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
        let chunks = PronunciationGuideProvider.guide(for: currentWord.text)?.spellingChunks ?? []
        puzzle = SpellingPuzzle(answer: currentWord.text, preferredChunks: chunks)
        hasCheckedPuzzle = false
    }

    private func syllableColor(_ index: Int) -> Color {
        let colors: [Color] = [.green, .orange, .blue, .pink, .teal]
        return colors[index % colors.count]
    }
}

private enum LearningStage: String, CaseIterable, Identifiable {
    case learn
    case read
    case spell

    var id: String { rawValue }

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
        padding(20)
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
            .padding(.horizontal, 8)
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
