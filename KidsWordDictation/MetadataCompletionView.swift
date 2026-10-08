import SwiftUI
import Translation

enum MetadataCompletion {
    static func missingLabels(
        americanPhonetic: String,
        britishPhonetic: String,
        translation: String,
        sentence: String = "",
        sentenceTranslation: String = ""
    ) -> [String] {
        var labels: [String] = []
        if WordTextNormalizer.displayText(for: americanPhonetic).isEmpty {
            labels.append("美式音标")
        }
        if WordTextNormalizer.displayText(for: britishPhonetic).isEmpty {
            labels.append("英式音标")
        }
        if WordTextNormalizer.displayText(for: translation).isEmpty {
            labels.append("中文释义")
        }
        if !WordTextNormalizer.displayText(for: sentence).isEmpty,
           WordTextNormalizer.displayText(for: sentenceTranslation).isEmpty {
            labels.append("例句中文")
        }
        return labels
    }

    @discardableResult
    static func fillMissing(
        for text: String,
        americanPhonetic: inout String,
        britishPhonetic: inout String,
        translation: inout String,
        sentence: inout String,
        sentenceTranslation: inout String
    ) -> Bool {
        let metadata = WordMetadataProvider.metadata(for: text)
        var changed = false

        if WordTextNormalizer.displayText(for: americanPhonetic).isEmpty, !metadata.americanPhonetic.isEmpty {
            americanPhonetic = metadata.americanPhonetic
            changed = true
        }
        if WordTextNormalizer.displayText(for: britishPhonetic).isEmpty, !metadata.britishPhonetic.isEmpty {
            britishPhonetic = metadata.britishPhonetic
            changed = true
        }
        if WordTextNormalizer.displayText(for: translation).isEmpty, !metadata.translation.isEmpty {
            translation = metadata.translation
            changed = true
        }
        if WordTextNormalizer.displayText(for: sentence).isEmpty, !metadata.sentence.isEmpty {
            sentence = metadata.sentence
            changed = true
        }
        if WordTextNormalizer.displayText(for: sentenceTranslation).isEmpty,
           sentence == metadata.sentence,
           !metadata.sentenceTranslation.isEmpty {
            sentenceTranslation = metadata.sentenceTranslation
            changed = true
        }

        return changed
    }

    static func mergedMetadata(
        for text: String,
        americanPhonetic: String,
        britishPhonetic: String,
        translation: String,
        sentence: String,
        sentenceTranslation: String
    ) -> WordMetadata {
        let metadata = WordMetadataProvider.metadata(for: text)
        let resolvedSentence = WordTextNormalizer.displayText(for: sentence).isEmpty ? metadata.sentence : sentence
        let resolvedSentenceTranslation: String
        if WordTextNormalizer.displayText(for: sentenceTranslation).isEmpty,
           resolvedSentence == metadata.sentence {
            resolvedSentenceTranslation = metadata.sentenceTranslation
        } else {
            resolvedSentenceTranslation = sentenceTranslation
        }
        return WordMetadata(
            americanPhonetic: WordTextNormalizer.displayText(for: americanPhonetic).isEmpty ? metadata.americanPhonetic : americanPhonetic,
            britishPhonetic: WordTextNormalizer.displayText(for: britishPhonetic).isEmpty ? metadata.britishPhonetic : britishPhonetic,
            translation: WordTextNormalizer.displayText(for: translation).isEmpty ? metadata.translation : translation,
            sentence: resolvedSentence,
            sentenceTranslation: resolvedSentenceTranslation
        )
    }
}

struct MetadataCompletionRow: View {
    let wordText: String
    let americanPhonetic: String
    let britishPhonetic: String
    let translation: String
    let sentence: String
    let sentenceTranslation: String
    let missingLabels: [String]
    let onApplyMetadata: (WordMetadata) -> Bool

    @State private var completionMessage = ""
    @State private var completionMessageIsSuccess = false
    @State private var isCompleting = false
    @State private var pendingTranslationMetadata: WordMetadata?
    @State private var translationConfiguration: TranslationSession.Configuration?

    var body: some View {
        if !missingLabels.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label("待补全：\(missingLabels.joined(separator: "、"))", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    Button {
                        completeMetadata()
                    } label: {
                        Label(isCompleting ? "补全中" : "一键补全", systemImage: isCompleting ? "hourglass" : "wand.and.stars")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 2)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(WordTextNormalizer.normalize(wordText).isEmpty || isCompleting)
                }

                if !completionMessage.isEmpty {
                    Text(completionMessage)
                        .font(.caption2)
                        .foregroundStyle(completionMessageIsSuccess ? .green : .secondary)
                }
            }
            .onChange(of: wordText) { _, _ in
                completionMessage = ""
            }
            .translationTask(translationConfiguration) { session in
                await runTranslation(session)
            }
        }
    }

    private func completeMetadata() {
        let offlineMetadata = MetadataCompletion.mergedMetadata(
            for: wordText,
            americanPhonetic: americanPhonetic,
            britishPhonetic: britishPhonetic,
            translation: translation,
            sentence: sentence,
            sentenceTranslation: sentenceTranslation
        )
        let didApplyOffline = onApplyMetadata(offlineMetadata)
        let remainingLabels = MetadataCompletion.missingLabels(
            americanPhonetic: offlineMetadata.americanPhonetic,
            britishPhonetic: offlineMetadata.britishPhonetic,
            translation: offlineMetadata.translation,
            sentence: offlineMetadata.sentence,
            sentenceTranslation: offlineMetadata.sentenceTranslation
        )

        if remainingLabels.isEmpty {
            setMessage(didApplyOffline ? "已从内置词库补全" : "已经是完整信息", isSuccess: true)
            return
        }

        let needsSystemTranslation = offlineMetadata.translation.isEmpty
            || (!offlineMetadata.sentence.isEmpty && offlineMetadata.sentenceTranslation.isEmpty)
        if needsSystemTranslation {
            setMessage("内置词库未完全命中，正在尝试系统翻译", isSuccess: false)
            beginTranslations(for: offlineMetadata)
        } else {
            setMessage("内置词库暂无对应音标，请手动编辑", isSuccess: false)
        }
    }

    @MainActor
    private func runTranslation(_ session: TranslationSession) async {
        guard var metadata = pendingTranslationMetadata else {
            isCompleting = false
            return
        }

        do {
            try await session.prepareTranslation()
            if metadata.translation.isEmpty {
                let response = try await session.translate(wordText)
                metadata.translation = WordTextNormalizer.displayText(for: response.targetText)
            }
            if !metadata.sentence.isEmpty && metadata.sentenceTranslation.isEmpty {
                let response = try await session.translate(metadata.sentence)
                metadata.sentenceTranslation = WordTextNormalizer.displayText(for: response.targetText)
            }
            _ = onApplyMetadata(metadata)
            let remainingLabels = MetadataCompletion.missingLabels(
                americanPhonetic: metadata.americanPhonetic,
                britishPhonetic: metadata.britishPhonetic,
                translation: metadata.translation,
                sentence: metadata.sentence,
                sentenceTranslation: metadata.sentenceTranslation
            )
            if remainingLabels.isEmpty {
                setMessage("已用内置词库和系统翻译补全", isSuccess: true)
            } else {
                setMessage("中文已补全，仍待补：\(remainingLabels.joined(separator: "、"))", isSuccess: false)
            }
        } catch {
            _ = onApplyMetadata(metadata)
            setMessage("系统翻译暂不可用：\(error.localizedDescription)。可手动编辑。", isSuccess: false)
        }

        pendingTranslationMetadata = nil
        isCompleting = false
    }

    @MainActor
    private func beginTranslations(for metadata: WordMetadata) {
        let needsWordTranslation = metadata.translation.isEmpty
        let needsSentenceTranslation = !metadata.sentence.isEmpty && metadata.sentenceTranslation.isEmpty
        guard needsWordTranslation || needsSentenceTranslation else {
            _ = onApplyMetadata(metadata)
            setMessage("已从内置词库补全", isSuccess: true)
            isCompleting = false
            return
        }

        isCompleting = true
        pendingTranslationMetadata = metadata
        translationConfiguration = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "zh-Hans")
        )
        translationConfiguration?.invalidate()
    }

    private func setMessage(_ message: String, isSuccess: Bool) {
        completionMessage = message
        completionMessageIsSuccess = isSuccess
    }
}
