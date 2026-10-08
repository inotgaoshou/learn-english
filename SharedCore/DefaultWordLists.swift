import Foundation

public enum DefaultWordLists {
    public static let u1 = WordList(
        title: "U1 单词",
        category: "KET",
        words: [
            "grandma",
            "grandad",
            "husband",
            "wife",
            "uncle",
            "aunt",
            "cousin",
            "son",
            "daughter",
            "sister",
            "brother",
            "grandson",
            "granddaughter",
            "university",
            "pet",
            "musical instrument"
        ].map { WordItem(text: $0) }
    )
}
