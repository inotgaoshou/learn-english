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
        let metadata = WordMetadataProvider.metadata(for: self.text)
        let cleanPhonetic = WordTextNormalizer.displayText(for: phonetic)
        self.phonetic = cleanPhonetic.isEmpty ? metadata.americanPhonetic : cleanPhonetic
        let cleanBritishPhonetic = WordTextNormalizer.displayText(for: britishPhonetic)
        self.britishPhonetic = cleanBritishPhonetic.isEmpty ? metadata.britishPhonetic : cleanBritishPhonetic
        let cleanTranslation = WordTextNormalizer.displayText(for: translation)
        self.translation = cleanTranslation.isEmpty ? metadata.translation : cleanTranslation
        let cleanSentence = WordTextNormalizer.displayText(for: sentence)
        self.sentence = cleanSentence.isEmpty ? metadata.sentence : cleanSentence
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
        let metadata = WordMetadataProvider.metadata(for: text)
        let decodedPhonetic = try container.decodeIfPresent(String.self, forKey: .phonetic) ?? ""
        phonetic = decodedPhonetic.isEmpty ? metadata.americanPhonetic : decodedPhonetic
        let decodedBritishPhonetic = try container.decodeIfPresent(String.self, forKey: .britishPhonetic) ?? ""
        britishPhonetic = decodedBritishPhonetic.isEmpty ? metadata.britishPhonetic : decodedBritishPhonetic
        let decodedTranslation = try container.decodeIfPresent(String.self, forKey: .translation) ?? ""
        translation = decodedTranslation.isEmpty ? metadata.translation : decodedTranslation
        let decodedSentence = try container.decodeIfPresent(String.self, forKey: .sentence) ?? ""
        sentence = decodedSentence.isEmpty ? metadata.sentence : decodedSentence
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

    public var missingMetadataLabels: [String] {
        var labels: [String] = []
        if WordTextNormalizer.displayText(for: phonetic).isEmpty {
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

    public var hasCompleteRequiredMetadata: Bool {
        missingMetadataLabels.isEmpty
    }

    @discardableResult
    public mutating func fillMissingMetadata() -> Bool {
        let metadata = WordMetadataProvider.metadata(for: text)
        var changed = false

        if WordTextNormalizer.displayText(for: phonetic).isEmpty, !metadata.americanPhonetic.isEmpty {
            phonetic = metadata.americanPhonetic
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
}

public struct WordMetadata: Equatable, Hashable {
    public var americanPhonetic: String
    public var britishPhonetic: String
    public var translation: String
    public var sentence: String

    public init(americanPhonetic: String = "", britishPhonetic: String = "", translation: String = "", sentence: String = "") {
        self.americanPhonetic = WordTextNormalizer.displayText(for: americanPhonetic)
        self.britishPhonetic = WordTextNormalizer.displayText(for: britishPhonetic)
        self.translation = WordTextNormalizer.displayText(for: translation)
        self.sentence = WordTextNormalizer.displayText(for: sentence)
    }
}

public enum WordMetadataProvider {
    public static func metadata(for text: String) -> WordMetadata {
        WordMetadata(
            americanPhonetic: WordPhoneticLookup.phonetic(for: text),
            britishPhonetic: WordPhoneticLookup.britishPhonetic(for: text),
            translation: WordTranslationLookup.translation(for: text),
            sentence: WordSentenceLookup.sentence(for: text)
        )
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
        "granny": "奶奶；外婆；祖母",
        "grandpa": "爷爷；外公；祖父",
        "grandad": "爷爷；外公",
        "granddad": "爷爷；外公",
        "grandparent": "祖父或祖母；外祖父或外祖母",
        "grandparents": "祖父母；外祖父母",
        "husband": "丈夫",
        "wife": "妻子；太太",
        "uncle": "叔叔；伯父；舅父；姑父；姨父",
        "aunt": "阿姨；姑母；姨母；伯母；婶母；舅母",
        "cousin": "堂兄弟姐妹；表兄弟姐妹",
        "nephew": "侄子；外甥",
        "niece": "侄女；外甥女",
        "son": "儿子",
        "daughter": "女儿",
        "sister": "姐妹；姐姐；妹妹",
        "sisters": "姐妹；姐姐妹妹",
        "brother": "兄弟；哥哥；弟弟",
        "brothers": "兄弟；哥哥弟弟",
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
        "friends": "朋友们",
        "best friend": "最好的朋友",
        "funny": "有趣的；滑稽的",
        "guitar": "吉他",
        "band": "乐队",
        "party": "聚会",
        "tonight": "今晚",
        "called": "名叫；被称为",
        "live": "居住；生活",
        "london": "伦敦",
        "mum": "妈妈",
        "dad": "爸爸",
        "musician": "音乐家",
        "village": "村庄",
        "town": "城镇",
        "north": "北方；北部",
        "small": "小的",
        "nearly": "几乎；将近",
        "older": "年龄较大的；更老的",
        "birthday": "生日",
        "week": "星期；周",
        "lunch": "午餐",
        "football": "足球",
        "match": "比赛",
        "study": "学习；研究",
        "hope": "希望",
        "sport": "运动",
        "poland": "波兰",
        "grandson": "孙子；外孙",
        "granddaughter": "孙女；外孙女",
        "university": "大学",
        "pet": "宠物",
        "musical instrument": "乐器",
        "chair": "椅子",
        "floor": "地板；楼层",
        "fridge": "冰箱",
        "light": "灯；光",
        "garage": "车库",
        "table": "桌子",
        "desk": "书桌；课桌",
        "sofa": "沙发",
        "bed": "床",
        "door": "门",
        "window": "窗户",
        "kitchen": "厨房",
        "bathroom": "浴室；卫生间",
        "bedroom": "卧室",
        "living room": "客厅",
        "dining room": "餐厅",
        "house": "房子",
        "home": "家",
        "wall": "墙",
        "garden": "花园",
        "cupboard": "橱柜；衣柜",
        "mirror": "镜子",
        "clock": "钟；时钟",
        "picture": "图画；照片",
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
        "granny": "/ˈɡræni/",
        "grandpa": "/ˈɡrændpɑ/",
        "grandad": "/ˈɡrændæd/",
        "granddad": "/ˈɡrændæd/",
        "grandparent": "/ˈɡrændperənt/",
        "grandparents": "/ˈɡrændperənts/",
        "husband": "/ˈhʌzbənd/",
        "wife": "/waɪf/",
        "uncle": "/ˈʌŋkəl/",
        "aunt": "/ænt/",
        "cousin": "/ˈkʌzən/",
        "nephew": "/ˈnefjuː/",
        "niece": "/niːs/",
        "son": "/sʌn/",
        "daughter": "/ˈdɔtɚ/",
        "sister": "/ˈsɪstɚ/",
        "sisters": "/ˈsɪstɚz/",
        "brother": "/ˈbrʌðɚ/",
        "brothers": "/ˈbrʌðɚz/",
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
        "friends": "/frendz/",
        "best friend": "/best frend/",
        "funny": "/ˈfʌni/",
        "guitar": "/ɡɪˈtɑːr/",
        "band": "/bænd/",
        "party": "/ˈpɑːrti/",
        "tonight": "/təˈnaɪt/",
        "called": "/kɔːld/",
        "live": "/lɪv/",
        "london": "/ˈlʌndən/",
        "mum": "/mʌm/",
        "dad": "/dæd/",
        "musician": "/mjuˈzɪʃən/",
        "village": "/ˈvɪlɪdʒ/",
        "town": "/taʊn/",
        "north": "/nɔːrθ/",
        "small": "/smɔːl/",
        "nearly": "/ˈnɪrli/",
        "older": "/ˈoʊldɚ/",
        "birthday": "/ˈbɝːθdeɪ/",
        "week": "/wiːk/",
        "lunch": "/lʌntʃ/",
        "football": "/ˈfʊtbɔːl/",
        "match": "/mætʃ/",
        "study": "/ˈstʌdi/",
        "hope": "/hoʊp/",
        "sport": "/spɔːrt/",
        "poland": "/ˈpoʊlənd/",
        "grandson": "/ˈɡrænsʌn/",
        "granddaughter": "/ˈɡrændɔtɚ/",
        "university": "/ˌjunəˈvɝsəti/",
        "pet": "/pet/",
        "musical instrument": "/ˈmjuːzɪkəl ˈɪnstrəmənt/",
        "chair": "/tʃer/",
        "floor": "/flɔːr/",
        "fridge": "/frɪdʒ/",
        "light": "/laɪt/",
        "garage": "/ɡəˈrɑːʒ/",
        "table": "/ˈteɪbəl/",
        "desk": "/desk/",
        "sofa": "/ˈsoʊfə/",
        "bed": "/bed/",
        "door": "/dɔːr/",
        "window": "/ˈwɪndoʊ/",
        "kitchen": "/ˈkɪtʃən/",
        "bathroom": "/ˈbæθruːm/",
        "bedroom": "/ˈbedruːm/",
        "living room": "/ˈlɪvɪŋ ruːm/",
        "dining room": "/ˈdaɪnɪŋ ruːm/",
        "house": "/haʊs/",
        "home": "/hoʊm/",
        "wall": "/wɔːl/",
        "garden": "/ˈɡɑːrdən/",
        "cupboard": "/ˈkʌbərd/",
        "mirror": "/ˈmɪrər/",
        "clock": "/klɑːk/",
        "picture": "/ˈpɪktʃɚ/",
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
        "granny": "/ˈɡræni/",
        "grandpa": "/ˈɡrændpɑː/",
        "grandad": "/ˈɡrændæd/",
        "granddad": "/ˈɡrændæd/",
        "grandparent": "/ˈɡrændpeərənt/",
        "grandparents": "/ˈɡrændpeərənts/",
        "husband": "/ˈhʌzbənd/",
        "wife": "/waɪf/",
        "uncle": "/ˈʌŋkəl/",
        "aunt": "/ɑːnt/",
        "cousin": "/ˈkʌzən/",
        "nephew": "/ˈnefjuː/",
        "niece": "/niːs/",
        "son": "/sʌn/",
        "daughter": "/ˈdɔːtə/",
        "sister": "/ˈsɪstə/",
        "sisters": "/ˈsɪstəz/",
        "brother": "/ˈbrʌðə/",
        "brothers": "/ˈbrʌðəz/",
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
        "friends": "/frendz/",
        "best friend": "/best frend/",
        "funny": "/ˈfʌni/",
        "guitar": "/ɡɪˈtɑː/",
        "band": "/bænd/",
        "party": "/ˈpɑːti/",
        "tonight": "/təˈnaɪt/",
        "called": "/kɔːld/",
        "live": "/lɪv/",
        "london": "/ˈlʌndən/",
        "mum": "/mʌm/",
        "dad": "/dæd/",
        "musician": "/mjuˈzɪʃən/",
        "village": "/ˈvɪlɪdʒ/",
        "town": "/taʊn/",
        "north": "/nɔːθ/",
        "small": "/smɔːl/",
        "nearly": "/ˈnɪəli/",
        "older": "/ˈəʊldə/",
        "birthday": "/ˈbɜːθdeɪ/",
        "week": "/wiːk/",
        "lunch": "/lʌntʃ/",
        "football": "/ˈfʊtbɔːl/",
        "match": "/mætʃ/",
        "study": "/ˈstʌdi/",
        "hope": "/həʊp/",
        "sport": "/spɔːt/",
        "poland": "/ˈpəʊlənd/",
        "grandson": "/ˈɡrænsʌn/",
        "granddaughter": "/ˈɡrændɔːtə/",
        "university": "/ˌjuːnɪˈvɜːsəti/",
        "pet": "/pet/",
        "musical instrument": "/ˈmjuːzɪkəl ˈɪnstrəmənt/",
        "chair": "/tʃeə/",
        "floor": "/flɔː/",
        "fridge": "/frɪdʒ/",
        "light": "/laɪt/",
        "garage": "/ˈɡærɑːʒ/",
        "table": "/ˈteɪbəl/",
        "desk": "/desk/",
        "sofa": "/ˈsəʊfə/",
        "bed": "/bed/",
        "door": "/dɔː/",
        "window": "/ˈwɪndəʊ/",
        "kitchen": "/ˈkɪtʃən/",
        "bathroom": "/ˈbɑːθruːm/",
        "bedroom": "/ˈbedruːm/",
        "living room": "/ˈlɪvɪŋ ruːm/",
        "dining room": "/ˈdaɪnɪŋ ruːm/",
        "house": "/haʊs/",
        "home": "/həʊm/",
        "wall": "/wɔːl/",
        "garden": "/ˈɡɑːdən/",
        "cupboard": "/ˈkʌbəd/",
        "mirror": "/ˈmɪrə/",
        "clock": "/klɒk/",
        "picture": "/ˈpɪktʃə/",
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
        "granny": "My granny lives in a small town.",
        "grandpa": "My grandpa likes football.",
        "grandparent": "A grandparent is part of a family.",
        "grandparents": "My grandparents live near us.",
        "nephew": "My nephew is seven years old.",
        "niece": "My niece likes music.",
        "child": "The child is reading a book.",
        "children": "The children are playing in the park.",
        "parent": "A parent can help with homework.",
        "parents": "I live with my parents.",
        "girl": "The girl is twelve years old.",
        "boy": "The boy plays football after school.",
        "young": "My brother is very young.",
        "youngest": "I am the youngest child in my family.",
        "friend": "My friend is good at playing the guitar.",
        "friends": "I am inviting all my friends.",
        "best friend": "My best friend is called Stef.",
        "funny": "She is really funny.",
        "guitar": "He can play the guitar.",
        "band": "They are in a band.",
        "party": "We are going to a school party.",
        "tonight": "They are playing at the school party tonight.",
        "called": "My best friend is called Stef.",
        "live": "I live in London.",
        "london": "London is a big city.",
        "mum": "My mum is a musician.",
        "dad": "My dad teaches at the university.",
        "musician": "My mum is a musician.",
        "village": "They live in a small village.",
        "town": "I live in a small town.",
        "north": "The town is in the north.",
        "small": "I live in a small town.",
        "nearly": "I am nearly thirteen.",
        "older": "I hope to study there when I am older.",
        "birthday": "It is my birthday next week.",
        "week": "My birthday is next week.",
        "lunch": "We are having lunch then.",
        "football": "We are going to a football match.",
        "match": "We are going to a football match.",
        "study": "I hope to study there.",
        "hope": "I hope to study there.",
        "sport": "She hates sport.",
        "poland": "Anya is from Poland.",
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
        "musical instrument": "The guitar is a musical instrument.",
        "chair": "Please sit on the chair.",
        "floor": "The bag is on the floor.",
        "fridge": "There is milk in the fridge.",
        "light": "Please turn on the light.",
        "garage": "The car is in the garage.",
        "table": "The book is on the table.",
        "desk": "I do my homework at my desk.",
        "sofa": "We sit on the sofa in the living room.",
        "bed": "The child is sleeping in bed.",
        "door": "Please close the door.",
        "window": "Open the window, please.",
        "kitchen": "My mum is in the kitchen.",
        "bathroom": "The bathroom is next to the bedroom.",
        "bedroom": "My bedroom is small.",
        "living room": "The sofa is in the living room.",
        "dining room": "We have dinner in the dining room.",
        "house": "This is my house.",
        "home": "I go home after school.",
        "wall": "There is a picture on the wall.",
        "garden": "There are flowers in the garden.",
        "cupboard": "The cups are in the cupboard.",
        "mirror": "There is a mirror in the bathroom.",
        "clock": "There is a clock on the wall.",
        "picture": "This is a picture of my family."
    ]

    public static func sentence(for text: String) -> String {
        glossary[WordTextNormalizer.normalize(text)] ?? ""
    }
}
