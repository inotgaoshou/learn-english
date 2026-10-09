import SwiftUI
import Translation
import UIKit

enum SystemSpellingSuggestionProvider {
    static func suggestion(for text: String) -> String? {
        let word = WordTextNormalizer.normalize(text)
        guard word.count >= 3,
              WordMetadataProvider.metadata(for: word).missingRequiredLabels.count == 3 else {
            return nil
        }

        let range = NSRange(location: 0, length: (word as NSString).length)
        let guesses = UITextChecker().guesses(forWordRange: range, in: word, language: "en_US") ?? []
        return SpellingSuggestionSelector.bestSuggestion(for: word, candidates: guesses)
    }
}

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

    static func mergingCurrentValues(
        americanPhonetic: String,
        britishPhonetic: String,
        translation: String,
        sentence: String,
        sentenceTranslation: String,
        with resolved: WordMetadata
    ) -> WordMetadata {
        var current = WordMetadata(
            americanPhonetic: americanPhonetic,
            britishPhonetic: britishPhonetic,
            translation: translation,
            sentence: sentence,
            sentenceTranslation: sentenceTranslation
        )
        current.fillMissing(from: resolved)
        return current
    }

    static func resolveOnline(
        text: String,
        current: WordMetadata,
        allowNetwork: Bool,
        refresh: Bool = false
    ) async -> WordMetadataResolution {
        let resolution = await WordMetadataCoordinator.shared.resolve(
            text: text,
            allowNetwork: allowNetwork,
            refresh: refresh
        )
        var merged = current
        merged.fillMissing(from: resolution.metadata)
        return WordMetadataResolution(
            metadata: merged,
            source: resolution.source,
            failureReason: resolution.failureReason
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
    var automaticallyComplete = false
    let onApplyMetadata: (WordMetadata) -> Bool

    @State private var completionMessage = ""
    @State private var completionMessageIsSuccess = false
    @State private var hasSpellingSuggestion = false
    @State private var isCompleting = false
    @State private var activeCompletionID: UUID?
    @State private var pendingTranslationMetadata: WordMetadata?
    @State private var translationConfiguration: TranslationSession.Configuration?
    @AppStorage(OnlineCompletionSettings.storageKey) private var onlineCompletionEnabled = true

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
                        Task { await completeMetadata() }
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
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(completionMessage)
                            .font(.caption2)
                            .foregroundStyle(completionMessageIsSuccess ? .green : .secondary)

                        if !completionMessageIsSuccess && !hasSpellingSuggestion && onlineCompletionEnabled {
                            Button("重新查询") {
                                Task { await completeMetadata(refresh: true) }
                            }
                            .font(.caption2.weight(.semibold))
                            .buttonStyle(.borderless)
                            .disabled(isCompleting)
                        }
                    }
                }
            }
            .onChange(of: wordText) { _, _ in
                activeCompletionID = nil
                isCompleting = false
                pendingTranslationMetadata = nil
                translationConfiguration = nil
                completionMessage = ""
                hasSpellingSuggestion = false
            }
            .translationTask(translationConfiguration) { session in
                await runTranslation(session)
            }
            .task(id: WordTextNormalizer.normalize(wordText)) {
                guard automaticallyComplete,
                      !WordTextNormalizer.normalize(wordText).isEmpty,
                      !missingLabels.isEmpty else { return }
                do {
                    try await Task.sleep(for: .milliseconds(600))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await completeMetadata()
            }
        }
    }

    @MainActor
    private func completeMetadata(refresh: Bool = false) async {
        guard !WordTextNormalizer.normalize(wordText).isEmpty else {
            completionMessage = ""
            return
        }
        if let suggestion = SystemSpellingSuggestionProvider.suggestion(for: wordText) {
            hasSpellingSuggestion = true
            setMessage("可能是 \(suggestion)，请先确认拼写后再补全", isSuccess: false)
            return
        }
        hasSpellingSuggestion = false
        let requestedWord = WordTextNormalizer.normalize(wordText)
        let requestID = UUID()
        activeCompletionID = requestID
        isCompleting = true
        let offlineMetadata = MetadataCompletion.mergedMetadata(
            for: wordText,
            americanPhonetic: americanPhonetic,
            britishPhonetic: britishPhonetic,
            translation: translation,
            sentence: sentence,
            sentenceTranslation: sentenceTranslation
        )
        let didApplyOffline = onApplyMetadata(offlineMetadata)
        let resolution = await MetadataCompletion.resolveOnline(
            text: wordText,
            current: offlineMetadata,
            allowNetwork: onlineCompletionEnabled,
            refresh: refresh
        )
        guard activeCompletionID == requestID,
              WordTextNormalizer.normalize(wordText) == requestedWord,
              !Task.isCancelled else {
            return
        }
        let resolvedMetadata = resolution.metadata
        let didApplyResolved = onApplyMetadata(resolvedMetadata)
        let remainingLabels = MetadataCompletion.missingLabels(
            americanPhonetic: resolvedMetadata.americanPhonetic,
            britishPhonetic: resolvedMetadata.britishPhonetic,
            translation: resolvedMetadata.translation,
            sentence: resolvedMetadata.sentence,
            sentenceTranslation: resolvedMetadata.sentenceTranslation
        )

        if remainingLabels.isEmpty {
            let didChange = didApplyOffline || didApplyResolved
            let sourceMessage: String
            switch resolution.source {
            case .dictionaryAPI:
                sourceMessage = "已通过在线词典补全"
            case .cache:
                sourceMessage = "已从本地缓存补全"
            default:
                sourceMessage = "已从内置资料补全"
            }
            setMessage(didChange ? sourceMessage : "已经是完整信息", isSuccess: true)
            activeCompletionID = nil
            isCompleting = false
            return
        }

        let needsSystemTranslation = resolvedMetadata.translation.isEmpty
            || (!resolvedMetadata.sentence.isEmpty && resolvedMetadata.sentenceTranslation.isEmpty)
        if needsSystemTranslation {
            let prefix = resolution.failureReason.map { "\($0)；" } ?? ""
            setMessage("\(prefix)正在使用系统翻译补充中文", isSuccess: false)
            beginTranslations(for: resolvedMetadata)
        } else {
            let reason = resolution.failureReason ?? (onlineCompletionEnabled ? "在线词典暂无对应音标" : "联网补全已关闭")
            setMessage("\(reason)，可手动编辑", isSuccess: false)
            activeCompletionID = nil
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
        activeCompletionID = nil
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
