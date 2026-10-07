import Foundation

public enum FreeDictionaryMetadataParser {
    public static func metadata(from data: Data) throws -> WordMetadata {
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        guard let entry = entries.first else {
            return WordMetadata()
        }

        let phonetics = entry.phonetics.filter { !$0.cleanText.isEmpty }
        let americanPhonetic = preferredPhonetic(in: phonetics, marker: "-us") ?? entry.cleanPhonetic
        let britishPhonetic = preferredPhonetic(in: phonetics, marker: "-uk")
            ?? preferredPhonetic(in: phonetics, marker: "-gb")
            ?? entry.cleanPhonetic
        let fallbackPhonetic = phonetics.first?.cleanText ?? entry.cleanPhonetic
        let example = entry.meanings
            .flatMap(\.definitions)
            .compactMap { WordTextNormalizer.displayText(for: $0.example ?? "") }
            .first { !$0.isEmpty } ?? ""

        return WordMetadata(
            americanPhonetic: americanPhonetic.isEmpty ? fallbackPhonetic : americanPhonetic,
            britishPhonetic: britishPhonetic.isEmpty ? fallbackPhonetic : britishPhonetic,
            translation: "",
            sentence: example
        )
    }

    private static func preferredPhonetic(in phonetics: [Phonetic], marker: String) -> String? {
        phonetics.first { phonetic in
            phonetic.audio?.lowercased().contains(marker) == true
        }?.cleanText
    }
}

private extension FreeDictionaryMetadataParser {
    struct Entry: Decodable {
        let phonetic: String?
        let phonetics: [Phonetic]
        let meanings: [Meaning]

        var cleanPhonetic: String {
            WordTextNormalizer.displayText(for: phonetic ?? "")
        }
    }

    struct Phonetic: Decodable {
        let text: String?
        let audio: String?

        var cleanText: String {
            WordTextNormalizer.displayText(for: text ?? "")
        }
    }

    struct Meaning: Decodable {
        let definitions: [Definition]
    }

    struct Definition: Decodable {
        let example: String?
    }
}
