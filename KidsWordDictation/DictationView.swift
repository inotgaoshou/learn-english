import SwiftUI

struct DictationView: View {
    let wordList: WordList
    let mode: DictationMode

    @State private var session: DictationSession
    @State private var answer = ""
    @State private var speechRate = 0.45
    @State private var repetitions = 2
    @State private var speechAccent: SpeechAccent = .american
    @StateObject private var speechService = SpeechService()

    init(wordList: WordList, mode: DictationMode) {
        self.wordList = wordList
        self.mode = mode
        self._session = State(initialValue: DictationSession(words: wordList.words, mode: mode))
    }

    var body: some View {
        VStack(spacing: 20) {
            if session.isFinished {
                finishedView
            } else {
                activeQuestionView
            }
        }
        .padding()
        .navigationTitle("听写")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            speakCurrent()
        }
        .onDisappear {
            speechService.stop()
        }
        .onChange(of: session.currentItem?.id) { _, _ in
            speakCurrent()
        }
    }

    private var activeQuestionView: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("第 \(min(session.currentIndex + 1, session.totalCount)) / \(session.totalCount) 题")
                        .font(.headline)
                    Text(mode.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if mode == .shuffled {
                        Text("本轮使用临时随机列表，不改变原单元顺序")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    speakCurrent()
                } label: {
                    Image(systemName: "speaker.wave.2.circle.fill")
                        .font(.system(size: 72))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放")

                playbackControls

                TextField("输入听到的单词", text: $answer)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .submitLabel(.done)
                    .onSubmit(submitAnswer)

                if let result = session.lastResult {
                    resultView(result)
                }

                HStack(spacing: 12) {
                    Button {
                        submitAnswer()
                    } label: {
                        Label("提交", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(WordTextNormalizer.normalize(answer).isEmpty)

                    Button {
                        moveNext()
                    } label: {
                        Label("下一题", systemImage: "arrow.forward.circle")
                    }
                    .buttonStyle(.bordered)
                }

                if mode == .shuffled {
                    shuffledQueueView
                }
            }
        }
    }

    private var playbackControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播放")
                .font(.headline)
                .foregroundStyle(.secondary)

            Picker("发音", selection: $speechAccent) {
                ForEach(SpeechAccent.allCases) { accent in
                    Text(accent.title).tag(accent)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            HStack {
                Text("速度")
                Slider(value: $speechRate, in: 0.3...0.58, step: 0.01)
            }

            Divider()

            HStack {
                Text("重复 \(repetitions) 次")
                Spacer()
                Stepper("重复次数", value: $repetitions, in: 1...5)
                    .labelsHidden()
            }

            Divider()

            Button {
                speechService.pauseOrContinue()
            } label: {
                Label(speechService.isPaused ? "继续" : "暂停", systemImage: speechService.isPaused ? "play.fill" : "pause.fill")
            }
            .disabled(!speechService.isSpeaking && !speechService.isPaused)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var shuffledQueueView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("临时打乱顺序", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Text("\(session.totalCount) 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    refreshShuffledQueue()
                } label: {
                    Label("刷新列表", systemImage: "arrow.triangle.2.circlepath")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ForEach(Array(session.queue.enumerated()), id: \.element.id) { index, item in
                let isCurrent = index == session.currentIndex
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isCurrent ? .white : .secondary)
                        .frame(width: 28, height: 28)
                        .background(isCurrent ? Color.accentColor : Color.secondary.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.text)
                                .font(.body.weight(isCurrent ? .semibold : .regular))
                            ForEach(phoneticRows(for: item), id: \.self) { row in
                                Text(row)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !item.translation.isEmpty {
                            Text(item.translation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if !item.missingMetadataLabels.isEmpty {
                            Text("待补全：\(item.missingMetadataLabels.joined(separator: "、"))")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        }
                        if !item.sentence.isEmpty {
                            Text(item.sentence)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    if isCurrent {
                        Text("当前")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        speechService.speak(item.text, rate: Float(speechRate), repetitions: repetitions, accent: speechAccent)
                    } label: {
                        Image(systemName: "speaker.wave.2.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("播放第 \(index + 1) 个单词")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .onTapGesture {
                    jumpToQuestion(index)
                }

                if index != session.queue.count - 1 {
                    Divider()
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var finishedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("完成")
                .font(.title.bold())

            Text("\(session.correctCount) / \(session.totalCount)")
                .font(.largeTitle.monospacedDigit())

            Button {
                restartRound()
            } label: {
                Label(mode == .shuffled ? "重新打乱再来一轮" : "再来一轮", systemImage: mode == .shuffled ? "shuffle" : "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultView(_ result: AnswerResult) -> some View {
        VStack(spacing: 6) {
            Label(result.isCorrect ? "正确" : "答案：\(result.expectedAnswer)", systemImage: result.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline)
                .foregroundStyle(result.isCorrect ? .green : .red)
            if !result.item.translation.isEmpty {
                Text(result.item.translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !result.item.missingMetadataLabels.isEmpty {
                Text("待补全：\(result.item.missingMetadataLabels.joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func submitAnswer() {
        session.submit(answer: answer)
    }

    private func moveNext() {
        session.moveNext()
        answer = ""
    }

    private func jumpToQuestion(_ index: Int) {
        let previousIndex = session.currentIndex
        session.move(to: index)
        answer = ""
        if previousIndex == index {
            speakCurrent()
        }
    }

    private func speakCurrent() {
        guard let current = session.currentItem else {
            return
        }
        speechService.speak(current.text, rate: Float(speechRate), repetitions: repetitions, accent: speechAccent)
    }

    private func restartRound() {
        session = DictationSession(words: wordList.words, mode: mode)
        answer = ""
    }

    private func refreshShuffledQueue() {
        guard mode == .shuffled else {
            return
        }
        let previousItemID = session.currentItem?.id
        restartRound()
        if previousItemID == session.currentItem?.id {
            speakCurrent()
        }
    }

    private func phoneticRows(for item: WordItem) -> [String] {
        let american = WordTextNormalizer.displayText(for: item.phonetic)
        let british = WordTextNormalizer.displayText(for: item.britishPhonetic)

        if american.isEmpty && british.isEmpty {
            return []
        }

        if !american.isEmpty && (british.isEmpty || american == british) {
            return ["美/英 \(american)"]
        }

        if american.isEmpty {
            return ["英 \(british)"]
        }

        return ["美 \(american)", "英 \(british)"]
    }
}
