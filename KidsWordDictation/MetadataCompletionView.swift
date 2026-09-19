import SwiftUI

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
    let missingLabels: [String]
    let onFillMissing: () -> Bool

    @State private var completionMessage = ""

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
                        completionMessage = onFillMissing() ? "已从内置词库补全" : "内置词库暂无，可手动编辑"
                    } label: {
                        Label("一键补全", systemImage: "wand.and.stars")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 2)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if !completionMessage.isEmpty {
                    Text(completionMessage)
                        .font(.caption2)
                        .foregroundStyle(completionMessage == "已从内置词库补全" ? .green : .secondary)
                }
            }
            .onChange(of: missingLabels) { _, _ in
                completionMessage = ""
            }
        }
    }
}
