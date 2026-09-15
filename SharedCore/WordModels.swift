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
        let cleanSentence = WordTextNormalizer.displayText(for: sentence)
        self.sentence = cleanSentence.isEmpty ? WordSentenceLookup.sentence(for: self.text) : cleanSentence
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
        let decodedPhonetic = try container.decodeIfPresent(String.self, forKey: .phonetic) ?? ""
        phonetic = decodedPhonetic.isEmpty ? WordPhoneticLookup.phonetic(for: text) : decodedPhonetic
        let decodedBritishPhonetic = try container.decodeIfPresent(String.self, forKey: .britishPhonetic) ?? ""
        britishPhonetic = decodedBritishPhonetic.isEmpty ? WordPhoneticLookup.britishPhonetic(for: text) : decodedBritishPhonetic
        let decodedTranslation = try container.decodeIfPresent(String.self, forKey: .translation) ?? ""
        translation = decodedTranslation.isEmpty ? WordTranslationLookup.translation(for: text) : decodedTranslation
        let decodedSentence = try container.decodeIfPresent(String.self, forKey: .sentence) ?? ""
        sentence = decodedSentence.isEmpty ? WordSentenceLookup.sentence(for: text) : decodedSentence
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
        "parent": "父亲或母亲；家长",
        "parents": "父母；家长",
        "family tree": "家谱；家庭关系图",
        "teenager": "青少年",
        "child": "儿童；孩子",
        "children": "儿童；孩子们",
        "girl": "女孩",
        "boy": "男孩",
        "young": "年轻的；年幼的",
        "youngest": "最年轻的；最小的",
        "friend": "朋友",
        "best friend": "最好的朋友",
        "funny": "有趣的；滑稽的",
        "guitar": "吉他",
        "band": "乐队",
        "party": "聚会",
        "tonight": "今晚",
        "called": "名叫；被称为",
        "live": "居住；生活",
        "london": "伦敦",
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
        "parent": "/ˈperənt/",
        "parents": "/ˈperənts/",
        "family tree": "/ˈfæməli triː/",
        "teenager": "/ˈtiːneɪdʒɚ/",
        "child": "/tʃaɪld/",
        "children": "/ˈtʃɪldrən/",
        "girl": "/ɡɝːl/",
        "boy": "/bɔɪ/",
        "young": "/jʌŋ/",
        "youngest": "/ˈjʌŋɡəst/",
        "friend": "/frend/",
        "best friend": "/best frend/",
        "funny": "/ˈfʌni/",
        "guitar": "/ɡɪˈtɑːr/",
        "band": "/bænd/",
        "party": "/ˈpɑːrti/",
        "tonight": "/təˈnaɪt/",
        "called": "/kɔːld/",
        "live": "/lɪv/",
        "london": "/ˈlʌndən/",
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
        "parent": "/ˈpeərənt/",
        "parents": "/ˈpeərənts/",
        "family tree": "/ˈfæməli triː/",
        "teenager": "/ˈtiːneɪdʒə/",
        "child": "/tʃaɪld/",
        "children": "/ˈtʃɪldrən/",
        "girl": "/ɡɜːl/",
        "boy": "/bɔɪ/",
        "young": "/jʌŋ/",
        "youngest": "/ˈjʌŋɡɪst/",
        "friend": "/frend/",
        "best friend": "/best frend/",
        "funny": "/ˈfʌni/",
        "guitar": "/ɡɪˈtɑː/",
        "band": "/bænd/",
        "party": "/ˈpɑːti/",
        "tonight": "/təˈnaɪt/",
        "called": "/kɔːld/",
        "live": "/lɪv/",
        "london": "/ˈlʌndən/",
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

public enum WordSentenceLookup {
    private static let glossary: [String: String] = [
        "family tree": "This is my family tree.",
        "teenager": "My sister is a teenager.",
        "child": "The child is reading a book.",
        "children": "The children are playing in the park.",
        "parent": "A parent can help with homework.",
        "parents": "I live with my parents.",
        "girl": "The girl is twelve years old.",
        "boy": "The boy plays football after school.",
        "young": "My brother is very young.",
        "youngest": "I am the youngest child in my family.",
        "friend": "My friend is good at playing the guitar.",
        "best friend": "My best friend is called Stef.",
        "funny": "She is really funny.",
        "guitar": "He can play the guitar.",
        "band": "They are in a band.",
        "party": "We are going to a school party.",
        "tonight": "They are playing at the school party tonight.",
        "called": "My best friend is called Stef.",
        "live": "I live in London.",
        "london": "London is a big city.",
        "grandma": "My grandma is very kind.",
        "grandad": "My grandad likes music.",
        "husband": "Her husband is a teacher.",
        "wife": "His wife is a doctor.",
        "uncle": "My uncle lives near us.",
        "aunt": "My aunt has a dog.",
        "cousin": "My cousin is thirteen.",
        "son": "Their son is at school.",
        "daughter": "Their daughter likes English.",
        "sister": "My sister is at university.",
        "brother": "My brother is younger than me.",
        "university": "Mel and Sue are at university.",
        "pet": "Our pet is a dog.",
        "musical instrument": "The guitar is a musical instrument."
    ]

    public static func sentence(for text: String) -> String {
        glossary[WordTextNormalizer.normalize(text)] ?? ""
    }
}
