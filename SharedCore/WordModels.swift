import Foundation

public struct WordItem: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var text: String
    public var normalizedText: String
    public var phonetic: String
    public var britishPhonetic: String
    public var translation: String
    public var sentence: String

    public init(id: UUID = UUID(), text: String, phonetic: String = "", britishPhonetic: String = "", translation: String = "", sentence: String = "") {
        self.id = id
        self.text = WordTextNormalizer.displayText(for: text)
        self.normalizedText = WordTextNormalizer.normalize(text)
        let cleanPhonetic = WordTextNormalizer.displayText(for: phonetic)
        self.phonetic = cleanPhonetic.isEmpty ? WordPhoneticLookup.phonetic(for: self.text) : cleanPhonetic
        let cleanBritishPhonetic = WordTextNormalizer.displayText(for: britishPhonetic)
        self.britishPhonetic = cleanBritishPhonetic.isEmpty ? WordPhoneticLookup.britishPhonetic(for: self.text) : cleanBritishPhonetic
        let cleanTranslation = WordTextNormalizer.displayText(for: translation)
        self.translation = cleanTranslation.isEmpty ? WordTranslationLookup.translation(for: self.text) : cleanTranslation
        self.sentence = WordTextNormalizer.displayText(for: sentence)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case normalizedText
        case phonetic
        case britishPhonetic
        case translation
        case sentence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        normalizedText = try container.decodeIfPresent(String.self, forKey: .normalizedText) ?? WordTextNormalizer.normalize(text)
        phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic) ?? WordPhoneticLookup.phonetic(for: text)
        britishPhonetic = try container.decodeIfPresent(String.self, forKey: .britishPhonetic) ?? WordPhoneticLookup.britishPhonetic(for: text)
        translation = try container.decodeIfPresent(String.self, forKey: .translation) ?? ""
        sentence = try container.decodeIfPresent(String.self, forKey: .sentence) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(normalizedText, forKey: .normalizedText)
        try container.encode(phonetic, forKey: .phonetic)
        try container.encode(britishPhonetic, forKey: .britishPhonetic)
        try container.encode(translation, forKey: .translation)
        try container.encode(sentence, forKey: .sentence)
    }
}

public struct WordList: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var category: String
    public var createdAt: Date
    public var words: [WordItem]

    public init(id: UUID = UUID(), title: String, category: String = "", createdAt: Date = Date(), words: [WordItem]) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.words = words
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case createdAt
        case words
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        words = try container.decode([WordItem].self, forKey: .words)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(words, forKey: .words)
    }
}

public enum WordTextNormalizer {
    public static func normalize(_ text: String) -> String {
        collapseWhitespace(in: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    public static func displayText(for text: String) -> String {
        collapseWhitespace(in: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapseWhitespace(in text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

public enum WordTranslationLookup {
    private static let glossary: [String: String] = [
        "grandma": "奶奶；外婆；祖母",
        "grandad": "爷爷；外公",
        "granddad": "爷爷；外公",
        "husband": "丈夫",
        "wife": "妻子；太太",
        "uncle": "叔叔；伯父；舅父；姑父；姨父",
        "aunt": "阿姨；姑母；姨母；伯母；婶母；舅母",
        "cousin": "堂兄弟姐妹；表兄弟姐妹",
        "son": "儿子",
        "daughter": "女儿",
        "sister": "姐妹；姐姐；妹妹",
        "brother": "兄弟；哥哥；弟弟",
        "grandson": "孙子；外孙",
        "granddaughter": "孙女；外孙女",
        "university": "大学",
        "pet": "宠物",
        "musical instrument": "乐器",
        "father": "父亲",
        "mother": "母亲",
        "family": "家庭；家人",
        "school": "学校",
        "teacher": "老师",
        "student": "学生",
        "book": "书",
        "apple": "苹果",
        "banana": "香蕉",
        "orange": "橙子",
        "cat": "猫",
        "dog": "狗"
    ]

    public static func translation(for text: String) -> String {
        glossary[WordTextNormalizer.normalize(text)] ?? ""
    }
}

public enum WordPhoneticLookup {
    private static let americanGlossary: [String: String] = [
        "grandma": "/ˈɡrænmɑ/",
        "grandad": "/ˈɡrændæd/",
        "granddad": "/ˈɡrændæd/",
        "husband": "/ˈhʌzbənd/",
        "wife": "/waɪf/",
        "uncle": "/ˈʌŋkəl/",
        "aunt": "/ænt/",
        "cousin": "/ˈkʌzən/",
        "son": "/sʌn/",
        "daughter": "/ˈdɔtɚ/",
        "sister": "/ˈsɪstɚ/",
        "brother": "/ˈbrʌðɚ/",
        "grandson": "/ˈɡrænsʌn/",
        "granddaughter": "/ˈɡrændɔtɚ/",
        "university": "/ˌjunəˈvɝsəti/",
        "pet": "/pet/",
        "musical instrument": "/ˈmjuːzɪkəl ˈɪnstrəmənt/",
        "father": "/ˈfɑðɚ/",
        "mother": "/ˈmʌðɚ/",
        "family": "/ˈfæməli/",
        "school": "/skuːl/",
        "teacher": "/ˈtitʃɚ/",
        "student": "/ˈstudənt/",
        "book": "/bʊk/",
        "apple": "/ˈæpəl/",
        "banana": "/bəˈnænə/",
        "orange": "/ˈɔrɪndʒ/",
        "cat": "/kæt/",
        "dog": "/dɔːɡ/"
    ]

    private static let britishGlossary: [String: String] = [
        "grandma": "/ˈɡrænmɑː/",
        "grandad": "/ˈɡrændæd/",
        "granddad": "/ˈɡrændæd/",
        "husband": "/ˈhʌzbənd/",
        "wife": "/waɪf/",
        "uncle": "/ˈʌŋkəl/",
        "aunt": "/ɑːnt/",
        "cousin": "/ˈkʌzən/",
        "son": "/sʌn/",
        "daughter": "/ˈdɔːtə/",
        "sister": "/ˈsɪstə/",
        "brother": "/ˈbrʌðə/",
        "grandson": "/ˈɡrænsʌn/",
        "granddaughter": "/ˈɡrændɔːtə/",
        "university": "/ˌjuːnɪˈvɜːsəti/",
        "pet": "/pet/",
        "musical instrument": "/ˈmjuːzɪkəl ˈɪnstrəmənt/",
        "father": "/ˈfɑːðə/",
        "mother": "/ˈmʌðə/",
        "family": "/ˈfæməli/",
        "school": "/skuːl/",
        "teacher": "/ˈtiːtʃə/",
        "student": "/ˈstjuːdənt/",
        "book": "/bʊk/",
        "apple": "/ˈæpəl/",
        "banana": "/bəˈnɑːnə/",
        "orange": "/ˈɒrɪndʒ/",
        "cat": "/kæt/",
        "dog": "/dɒɡ/"
    ]

    public static func phonetic(for text: String) -> String {
        americanGlossary[WordTextNormalizer.normalize(text)] ?? ""
    }

    public static func britishPhonetic(for text: String) -> String {
        britishGlossary[WordTextNormalizer.normalize(text)] ?? ""
    }
}
