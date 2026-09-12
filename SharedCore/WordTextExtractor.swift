import Foundation

public enum WordTextExtractor {
    private static let leadingNumberPattern = #"^\s*\d+[\.\)、\)]?\s*"#
    private static let partOfSpeechPattern = #"(?i)\b(?:n|v|vt|vi|adj|adv|prep|pron|conj|interj|int|num|art|aux|abbr)\.\s*"#
    private static let numberedEntryBoundaryPattern = #"\s+(?=\d+[\.\)]\s*[A-Za-z])"#
    private static let manualSeparatorPattern = #"\s*(?:=|:|：|-{2,}|—)\s*"#
    private static let partOfSpeechMarkers: Set<String> = [
        "n", "v", "vt", "vi", "adj", "adv", "prep", "pron", "conj", "interj", "int", "num", "art", "aux", "abbr"
    ]

    public static func extractWords(from recognizedText: String) -> [WordItem] {
        var seen = Set<String>()
        var words: [WordItem] = []

        for line in expandedLines(from: recognizedText) {
            guard let candidate = extractCandidate(from: line) else {
                continue
            }

            let item = WordItem(text: candidate.text, translation: candidate.translation)
            guard !item.normalizedText.isEmpty, seen.insert(item.normalizedText).inserted else {
                continue
            }
            words.append(item)
        }

        return words
    }

    private static func expandedLines(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .flatMap { line in
                line.replacingMatches(pattern: numberedEntryBoundaryPattern, with: "\n")
                    .components(separatedBy: .newlines)
            }
    }

    private static func extractCandidate(from line: String) -> (text: String, translation: String)? {
        let cleanedLine = line
            .replacingMatches(pattern: leadingNumberPattern, with: "")

        let parts = cleanedLine.splitEnglishAndTranslation(separatorPattern: manualSeparatorPattern)
        var candidate = parts.english
            .replacingMatches(pattern: partOfSpeechPattern, with: " ")
            .lettersAndPhraseSeparatorsOnly()

        candidate = WordTextNormalizer.displayText(for: candidate)
        guard isUsefulCandidate(candidate, translation: parts.translation) else {
            return nil
        }
        return (candidate, parts.translation)
    }

    private static func isUsefulCandidate(_ candidate: String, translation: String) -> Bool {
        let normalized = WordTextNormalizer.normalize(candidate)
        guard !normalized.isEmpty else {
            return false
        }

        let tokens = normalized.split(separator: " ").map(String.init)
        guard !tokens.contains(where: { partOfSpeechMarkers.contains($0) }) else {
            return false
        }

        guard !containsIsolatedNoiseToken(tokens) else {
            return false
        }

        guard !looksLikeShortUppercaseNoise(candidate) else {
            return false
        }

        guard !looksLikeUnknownShortNoise(normalized: normalized, translation: translation) else {
            return false
        }

        return tokens.contains { token in
            token.count > 1 || token == "a" || token == "i"
        }
    }

    private static func containsIsolatedNoiseToken(_ tokens: [String]) -> Bool {
        tokens.contains { token in
            token.count == 1 && token != "a" && token != "i"
        }
    }

    private static func looksLikeShortUppercaseNoise(_ candidate: String) -> Bool {
        let letters = candidate.filter { $0.isLetter }
        guard (2...4).contains(letters.count) else {
            return false
        }
        return letters.allSatisfy { $0.isUppercase }
    }

    private static func looksLikeUnknownShortNoise(normalized: String, translation: String) -> Bool {
        guard !containsCJK(translation) else {
            return false
        }

        if !WordTranslationLookup.translation(for: normalized).isEmpty || !WordPhoneticLookup.phonetic(for: normalized).isEmpty {
            return false
        }

        let letterCount = normalized.filter { $0.isLetter }.count
        return letterCount <= 3
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }
}

private extension String {
    func replacingMatches(pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return self
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: replacement)
    }

    func splitEnglishAndTranslation(separatorPattern: String) -> (english: String, translation: String) {
        if let regex = try? NSRegularExpression(pattern: separatorPattern),
           let match = regex.firstMatch(in: self, range: NSRange(startIndex..<endIndex, in: self)),
           let range = Range(match.range, in: self) {
            let left = String(self[..<range.lowerBound])
            let right = String(self[range.upperBound...])
            return (left, right.cleanedTranslation())
        }

        guard let index = firstIndexOfMeaning() else {
            return (self, "")
        }

        return (String(self[..<index]), String(self[index...]).cleanedTranslation())
    }

    func firstIndexOfMeaning() -> String.Index? {
        guard let cjkScalarIndex = unicodeScalars.firstIndex(where: { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }), let cjkIndex = String.Index(cjkScalarIndex, within: self) else {
            return nil
        }

        guard cjkIndex > startIndex else {
            return cjkIndex
        }

        let previous = index(before: cjkIndex)
        return self[previous] == "（" || self[previous] == "(" ? previous : cjkIndex
    }

    func cleanedTranslation() -> String {
        replacingMatches(pattern: #"(?i)\b(?:n|v|vt|vi|adj|adv|prep|pron|conj|interj|int|num|art|aux|abbr)\.\s*"#, with: "")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func lettersAndPhraseSeparatorsOnly() -> String {
        var scalars = String.UnicodeScalarView()
        let space = UnicodeScalar(" ")

        for scalar in unicodeScalars {
            let isLetter = (65...90).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value))
            let isPhraseSeparator = scalar == space || scalar == "-" || scalar == "'" || scalar == "’"
            scalars.append(isLetter || isPhraseSeparator ? scalar : space)
        }

        return String(scalars)
    }
}
