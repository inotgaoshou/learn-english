import SwiftUI
import Translation

enum MetadataCompletion {
    static func missingLabels(americanPhonetic: String, britishPhonetic: String, translation: String) -> [String] {
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
        return labels
    }

    @discardableResult
    static func fillMissing(
        for text: String,
        americanPhonetic: inout String,
        britishPhonetic: inout String,
        translation: inout String,
        sentence: inout String
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

        return changed
    }

    static func mergedMetadata(
        for text: String,
        americanPhonetic: String,
        britishPhonetic: String,
        translation: String,
        sentence: String
    ) -> WordMetadata {
        let metadata = WordMetadataProvider.metadata(for: text)
        return WordMetadata(
            americanPhonetic: WordTextNormalizer.displayText(for: americanPhonetic).isEmpty ? metadata.americanPhonetic : americanPhonetic,
            britishPhonetic: WordTextNormalizer.displayText(for: britishPhonetic).isEmpty ? metadata.britishPhonetic : britishPhonetic,
            translation: WordTextNormalizer.displayText(for: translation).isEmpty ? metadata.translation : translation,
            sentence: WordTextNormalizer.displayText(for: sentence).isEmpty ? metadata.sentence : sentence
        )
    }
}

struct MetadataCompletionRow: View {
    let wordText: String
    let americanPhonetic: String
    let britishPhonetic: String
    let translation: String
    let sentence: String
    let missingLabels: [String]
    let onApplyMetadata: (WordMetadata) -> Bool

    @State private var completionMessage = ""
    @State private var completionMessageIsSuccess = false
    @State private var isCompleting = false
    @State private var pendingTranslationText = ""
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
            .onChange(of: missingLabels) { _, _ in
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
            sentence: sentence
        )
        let didApplyOffline = onApplyMetadata(offlineMetadata)
        let remainingLabels = MetadataCompletion.missingLabels(
            americanPhonetic: offlineMetadata.americanPhonetic,
            britishPhonetic: offlineMetadata.britishPhonetic,
            translation: offlineMetadata.translation
        )

        if remainingLabels.isEmpty {
            setMessage(didApplyOffline ? "已从内置词库补全" : "已经是完整信息", isSuccess: true)
            return
        }

        Task {
            await completeOnline(from: offlineMetadata)
        }
    }

    @MainActor
    private func completeOnline(from baseMetadata: WordMetadata) async {
        isCompleting = true
        setMessage("内置词库未完全命中，正在联网补全", isSuccess: false)

        do {
            let onlineMetadata = try await OnlineWordMetadataService().metadata(for: wordText)
            let mergedMetadata = WordMetadata(
                americanPhonetic: baseMetadata.americanPhonetic.isEmpty ? onlineMetadata.americanPhonetic : baseMetadata.americanPhonetic,
                britishPhonetic: baseMetadata.britishPhonetic.isEmpty ? onlineMetadata.britishPhonetic : baseMetadata.britishPhonetic,
                translation: baseMetadata.translation,
                sentence: baseMetadata.sentence.isEmpty ? onlineMetadata.sentence : baseMetadata.sentence
            )

            if mergedMetadata.translation.isEmpty {
                pendingTranslationText = wordText
                pendingTranslationMetadata = mergedMetadata
                translationConfiguration = TranslationSession.Configuration(
                    source: Locale.Language(identifier: "en"),
                    target: Locale.Language(identifier: "zh-Hans")
                )
                translationConfiguration?.invalidate()
            } else {
                _ = onApplyMetadata(mergedMetadata)
                setMessage("已联网补全", isSuccess: true)
                isCompleting = false
            }
        } catch {
            setMessage("联网补全失败：\(error.localizedDescription)。可手动编辑。", isSuccess: false)
            isCompleting = false
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
            let response = try await session.translate(pendingTranslationText)
            metadata.translation = WordTextNormalizer.displayText(for: response.targetText)
            _ = onApplyMetadata(metadata)
            setMessage("已联网补全", isSuccess: true)
        } catch {
            _ = onApplyMetadata(metadata)
            setMessage("音标已补全，中文翻译暂不可用：\(error.localizedDescription)。", isSuccess: false)
        }

        pendingTranslationText = ""
        pendingTranslationMetadata = nil
        isCompleting = false
    }

    private func setMessage(_ message: String, isSuccess: Bool) {
        completionMessage = message
        completionMessageIsSuccess = isSuccess
    }
}
