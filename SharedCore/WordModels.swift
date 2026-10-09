import Foundation

public struct WordItem: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var text: String
    public var normalizedText: String
    public var phonetic: String
    public var britishPhonetic: String
    public var translation: String
    public var sentence: String
    public var sentenceTranslation: String

    public init(id: UUID = UUID(), text: String, phonetic: String = "", britishPhonetic: String = "", translation: String = "", sentence: String = "", sentenceTranslation: String = "") {
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
        let cleanSentenceTranslation = WordTextNormalizer.displayText(for: sentenceTranslation)
        self.sentenceTranslation = cleanSentenceTranslation.isEmpty && self.sentence == metadata.sentence
            ? metadata.sentenceTranslation
            : cleanSentenceTranslation
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case normalizedText
        case phonetic
        case britishPhonetic
        case translation
        case sentence
        case sentenceTranslation
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
        let decodedSentenceTranslation = try container.decodeIfPresent(String.self, forKey: .sentenceTranslation) ?? ""
        sentenceTranslation = decodedSentenceTranslation.isEmpty && sentence == metadata.sentence
            ? metadata.sentenceTranslation
            : decodedSentenceTranslation
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
        try container.encode(sentenceTranslation, forKey: .sentenceTranslation)
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
        if WordTextNormalizer.displayText(for: sentenceTranslation).isEmpty,
           sentence == metadata.sentence,
           !metadata.sentenceTranslation.isEmpty {
            sentenceTranslation = metadata.sentenceTranslation
            changed = true
        }

        return changed
    }
}

public struct WordMetadata: Codable, Equatable, Hashable, Sendable {
    public var americanPhonetic: String
    public var britishPhonetic: String
    public var translation: String
    public var sentence: String
    public var sentenceTranslation: String

    public init(americanPhonetic: String = "", britishPhonetic: String = "", translation: String = "", sentence: String = "", sentenceTranslation: String = "") {
        self.americanPhonetic = WordTextNormalizer.displayText(for: americanPhonetic)
        self.britishPhonetic = WordTextNormalizer.displayText(for: britishPhonetic)
        self.translation = WordTextNormalizer.displayText(for: translation)
        self.sentence = WordTextNormalizer.displayText(for: sentence)
        self.sentenceTranslation = WordTextNormalizer.displayText(for: sentenceTranslation)
    }
}

public enum WordMetadataProvider {
    public static func metadata(for text: String) -> WordMetadata {
        WordMetadata(
            americanPhonetic: WordPhoneticLookup.phonetic(for: text),
            britishPhonetic: WordPhoneticLookup.britishPhonetic(for: text),
            translation: WordTranslationLookup.translation(for: text),
            sentence: WordSentenceLookup.sentence(for: text),
            sentenceTranslation: WordSentenceTranslationLookup.translation(for: text)
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
        "message": "消息；信息",
        "note": "笔记；便条",
        "guess": "猜；猜测",
        "group": "小组；群体",
        "golden": "金色的；金制的",
        "partner": "搭档；伙伴",
        "grey": "灰色；灰色的",
        "gray": "灰色；灰色的",
        "listen": "听",
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
        "dog": "狗",
        "science": "科学",
        "robot": "机器人",
        "jump": "跳；跳跃",
        "rope": "绳；绳索",
        "hard-working": "勤奋的；努力工作的",
        "stair": "楼梯；梯级",
        "roof": "屋顶",
        "lift": "电梯；抬起",
        "start": "开始；出发",
        "invitation": "邀请；请柬",
        "worry": "担心；担忧",
        "doctor": "医生；博士",
        "potato": "土豆；马铃薯"
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
        "message": "/ˈmesɪdʒ/",
        "note": "/noʊt/",
        "guess": "/ɡes/",
        "group": "/ɡruːp/",
        "golden": "/ˈɡoʊldən/",
        "partner": "/ˈpɑːrtnɚ/",
        "grey": "/ɡreɪ/",
        "gray": "/ɡreɪ/",
        "listen": "/ˈlɪsən/",
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
        "dog": "/dɔːɡ/",
        "science": "/ˈsaɪəns/",
        "robot": "/ˈroʊbɑːt/",
        "jump": "/dʒʌmp/",
        "rope": "/roʊp/",
        "hard-working": "/ˌhɑːrdˈwɝːkɪŋ/",
        "stair": "/ster/",
        "roof": "/ruːf/",
        "lift": "/lɪft/",
        "start": "/stɑːrt/",
        "invitation": "/ˌɪnvɪˈteɪʃən/",
        "worry": "/ˈwɝːi/",
        "doctor": "/ˈdɑːktɚ/",
        "potato": "/pəˈteɪtoʊ/"
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
        "message": "/ˈmesɪdʒ/",
        "note": "/nəʊt/",
        "guess": "/ɡes/",
        "group": "/ɡruːp/",
        "golden": "/ˈɡəʊldən/",
        "partner": "/ˈpɑːtnə/",
        "grey": "/ɡreɪ/",
        "gray": "/ɡreɪ/",
        "listen": "/ˈlɪsən/",
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
        "dog": "/dɒɡ/",
        "science": "/ˈsaɪəns/",
        "robot": "/ˈrəʊbɒt/",
        "jump": "/dʒʌmp/",
        "rope": "/rəʊp/",
        "hard-working": "/ˌhɑːdˈwɜːkɪŋ/",
        "stair": "/steə/",
        "roof": "/ruːf/",
        "lift": "/lɪft/",
        "start": "/stɑːt/",
        "invitation": "/ˌɪnvɪˈteɪʃən/",
        "worry": "/ˈwʌri/",
        "doctor": "/ˈdɒktə/",
        "potato": "/pəˈteɪtəʊ/"
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
        "grandson": "Their grandson is eight years old.",
        "granddaughter": "Their granddaughter likes music.",
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
        "picture": "This is a picture of my family.",
        "message": "I sent a message to my friend.",
        "note": "Please write a note in your book.",
        "guess": "Can you guess the answer?",
        "group": "We work in a group.",
        "golden": "The golden key is on the table.",
        "partner": "Talk to your partner.",
        "grey": "The sky is grey today.",
        "gray": "The sky is gray today.",
        "listen": "Please listen to the teacher.",
        "science": "Science helps us understand the world.",
        "robot": "The robot can move its arms.",
        "jump": "Jump over the rope.",
        "rope": "The children are jumping rope.",
        "hard-working": "She is a hard-working student.",
        "stair": "Be careful on the stair.",
        "roof": "The bird is on the roof.",
        "lift": "Take the lift to the third floor.",
        "start": "The lesson will start at nine.",
        "invitation": "I received an invitation to the party.",
        "worry": "Do not worry about the test.",
        "doctor": "My mother is a doctor.",
        "potato": "You can taste the potato."
    ]

    public static func sentence(for text: String) -> String {
        glossary[WordTextNormalizer.normalize(text)] ?? ""
    }
}

public enum WordSentenceTranslationLookup {
    private static let glossary: [String: String] = [
        "family tree": "这是我的家谱。",
        "teenager": "我的姐姐是一名青少年。",
        "granny": "我的奶奶住在一个小镇上。",
        "grandpa": "我的爷爷喜欢足球。",
        "grandparent": "祖父母是家庭的一员。",
        "grandparents": "我的祖父母住在我们附近。",
        "nephew": "我的侄子七岁。",
        "niece": "我的侄女喜欢音乐。",
        "child": "这个孩子正在读书。",
        "children": "孩子们正在公园里玩。",
        "parent": "家长可以帮助完成作业。",
        "parents": "我和父母住在一起。",
        "girl": "这个女孩十二岁。",
        "boy": "这个男孩放学后踢足球。",
        "young": "我的弟弟年龄很小。",
        "youngest": "我是家里最小的孩子。",
        "friend": "我的朋友很擅长弹吉他。",
        "friends": "我正在邀请我所有的朋友。",
        "best friend": "我最好的朋友叫斯特夫。",
        "funny": "她真的很有趣。",
        "guitar": "他会弹吉他。",
        "band": "他们是乐队成员。",
        "party": "我们要去参加学校聚会。",
        "tonight": "他们今晚将在学校聚会上演出。",
        "called": "我最好的朋友叫斯特夫。",
        "live": "我住在伦敦。",
        "london": "伦敦是一座大城市。",
        "mum": "我的妈妈是一名音乐家。",
        "dad": "我的爸爸在大学教书。",
        "musician": "我的妈妈是一名音乐家。",
        "village": "他们住在一个小村庄里。",
        "town": "我住在一个小镇上。",
        "north": "这个小镇在北方。",
        "small": "我住在一个小镇上。",
        "nearly": "我快十三岁了。",
        "older": "我希望长大后去那里学习。",
        "birthday": "下周是我的生日。",
        "week": "我的生日在下周。",
        "lunch": "到时候我们正在吃午饭。",
        "football": "我们要去看一场足球比赛。",
        "match": "我们要去看一场足球比赛。",
        "study": "我希望去那里学习。",
        "hope": "我希望去那里学习。",
        "sport": "她讨厌运动。",
        "poland": "安雅来自波兰。",
        "grandma": "我的奶奶非常和蔼。",
        "grandad": "我的爷爷喜欢音乐。",
        "husband": "她的丈夫是一名老师。",
        "wife": "他的妻子是一名医生。",
        "uncle": "我的叔叔住在我们附近。",
        "aunt": "我的姑姑养了一只狗。",
        "cousin": "我的表兄弟十三岁。",
        "son": "他们的儿子在上学。",
        "daughter": "他们的女儿喜欢英语。",
        "sister": "我的姐姐在上大学。",
        "brother": "我的弟弟比我小。",
        "grandson": "他们的孙子八岁。",
        "granddaughter": "他们的孙女喜欢音乐。",
        "university": "梅尔和苏在上大学。",
        "pet": "我们的宠物是一只狗。",
        "musical instrument": "吉他是一种乐器。",
        "chair": "请坐在椅子上。",
        "floor": "书包在地板上。",
        "fridge": "冰箱里有牛奶。",
        "light": "请把灯打开。",
        "garage": "汽车在车库里。",
        "table": "书在桌子上。",
        "desk": "我在书桌前做作业。",
        "sofa": "我们坐在客厅的沙发上。",
        "bed": "孩子正在床上睡觉。",
        "door": "请关门。",
        "window": "请打开窗户。",
        "kitchen": "我妈妈在厨房里。",
        "bathroom": "浴室在卧室旁边。",
        "bedroom": "我的卧室很小。",
        "living room": "沙发在客厅里。",
        "dining room": "我们在餐厅吃晚饭。",
        "house": "这是我的房子。",
        "home": "我放学后回家。",
        "wall": "墙上有一幅画。",
        "garden": "花园里有花。",
        "cupboard": "杯子在橱柜里。",
        "mirror": "浴室里有一面镜子。",
        "clock": "墙上有一个钟。",
        "picture": "这是我的全家福。",
        "message": "我给朋友发了一条消息。",
        "note": "请在书上写一条笔记。",
        "guess": "你能猜出答案吗？",
        "group": "我们在小组里合作。",
        "golden": "金色的钥匙在桌子上。",
        "partner": "和你的搭档交谈。",
        "grey": "今天的天空是灰色的。",
        "gray": "今天的天空是灰色的。",
        "listen": "请听老师讲。",
        "science": "科学帮助我们了解世界。",
        "robot": "这个机器人会移动手臂。",
        "jump": "跳过这根绳子。",
        "rope": "孩子们正在跳绳。",
        "hard-working": "她是一名勤奋的学生。",
        "stair": "走楼梯时要小心。",
        "roof": "鸟儿在屋顶上。",
        "lift": "乘电梯到三楼。",
        "start": "课程将在九点开始。",
        "invitation": "我收到了一张聚会请柬。",
        "worry": "不要担心这次考试。",
        "doctor": "我的妈妈是一名医生。",
        "potato": "你可以尝尝这个土豆。"
    ]

    public static func translation(for text: String) -> String {
        glossary[WordTextNormalizer.normalize(text)] ?? ""
    }
}
