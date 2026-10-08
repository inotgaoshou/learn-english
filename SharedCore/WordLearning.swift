import Foundation

public enum LearningStage: String, CaseIterable, Identifiable, Hashable {
    case learn
    case read
    case select
    case spell
    case write

    public var id: String { rawValue }
}

public enum PronunciationUnitKind: String, Equatable, Hashable {
    case regular
    case letterGroup
    case irregular
    case silent
}

public struct LearningProgress: Equatable {
    private var completedByWord: [UUID: Set<LearningStage>] = [:]

    public init() {}

    public mutating func markComplete(_ stage: LearningStage, for wordID: UUID) {
        completedByWord[wordID, default: []].insert(stage)
    }

    public func completedStages(for wordID: UUID) -> Set<LearningStage> {
        completedByWord[wordID] ?? []
    }
}

public struct PronunciationUnit: Identifiable, Equatable, Hashable {
    public let id: String
    public let letters: String
    public let americanIPA: String
    public let britishIPA: String
    public let kind: PronunciationUnitKind

    public init(
        id: String = UUID().uuidString,
        letters: String,
        americanIPA: String,
        britishIPA: String = "",
        kind: PronunciationUnitKind = .regular
    ) {
        self.id = id
        self.letters = letters
        self.americanIPA = americanIPA
        self.britishIPA = britishIPA.isEmpty ? americanIPA : britishIPA
        self.kind = kind
    }

    public var isSilent: Bool {
        kind == .silent
    }
}

public struct PronunciationSyllable: Identifiable, Equatable, Hashable {
    public let id: String
    public let text: String
    public let units: [PronunciationUnit]

    public init(id: String = UUID().uuidString, text: String, units: [PronunciationUnit]) {
        self.id = id
        self.text = text
        self.units = units
    }
}

public struct PronunciationGuide: Equatable, Hashable {
    public let word: String
    public let syllables: [PronunciationSyllable]

    public init(word: String, syllables: [PronunciationSyllable]) {
        self.word = word
        self.syllables = syllables
    }

    public var units: [PronunciationUnit] {
        syllables.flatMap(\.units)
    }

    public var spellingChunks: [String] {
        syllables.map(\.text)
    }

    public var displaySyllableTexts: [String] {
        let words = WordTextNormalizer.displayText(for: word)
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
        guard words.count > 1 else {
            return spellingChunks
        }

        var offset = 0
        let wordBreakOffsets = Set(words.dropLast().map { part -> Int in
            offset += part.count
            return offset
        })
        var consumedCharacters = 0

        return syllables.map { syllable in
            let prefix = wordBreakOffsets.contains(consumedCharacters) ? " " : ""
            consumedCharacters += syllable.text.count
            return prefix + syllable.text
        }
    }

    public var hasReliablePhonics: Bool {
        guard !units.isEmpty else {
            return false
        }
        let unitText = WordTextNormalizer.normalize(units.map(\.letters).joined())
        let wordText = WordTextNormalizer.normalize(word).replacingOccurrences(of: " ", with: "")
        return unitText == wordText
            && units.allSatisfy { $0.isSilent || !$0.americanIPA.isEmpty }
    }

    public var spellingPieces: [String] {
        let phraseWords = WordTextNormalizer.displayText(for: word)
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
        if phraseWords.count > 1 {
            return phraseWords
        }

        let unitPieces = units.map(\.letters)
        if unitPieces.count > 1,
           WordTextNormalizer.normalize(unitPieces.joined()) == WordTextNormalizer.normalize(word) {
            return unitPieces
        }

        return WordTextNormalizer.displayText(for: word).map(String.init)
    }
}

public struct SelectionExercise: Equatable {
    public let answer: WordItem
    public let options: [WordItem]
    public private(set) var selectedID: WordItem.ID?

    public init(answer: WordItem, candidates: [WordItem], optionLimit: Int = 4) {
        var generator = SystemRandomNumberGenerator()
        self.init(answer: answer, candidates: candidates, optionLimit: optionLimit, randomNumberGenerator: &generator)
    }

    public init<RNG: RandomNumberGenerator>(
        answer: WordItem,
        candidates: [WordItem],
        optionLimit: Int = 4,
        randomNumberGenerator: inout RNG
    ) {
        var seen = Set<String>()
        let uniqueCandidates = candidates.filter {
            !$0.normalizedText.isEmpty && seen.insert($0.normalizedText).inserted
        }
        let distractors = uniqueCandidates
            .filter { $0.normalizedText != answer.normalizedText }
            .shuffled(using: &randomNumberGenerator)
        let limit = max(2, optionLimit)
        var values = [answer] + distractors.prefix(limit - 1)
        values.shuffle(using: &randomNumberGenerator)
        options = values
        self.answer = answer
        selectedID = nil
    }

    public var selectedOption: WordItem? {
        options.first { $0.id == selectedID }
    }

    public var isCorrect: Bool {
        selectedOption?.normalizedText == answer.normalizedText
    }

    public mutating func select(_ id: WordItem.ID) {
        guard options.contains(where: { $0.id == id }) else {
            return
        }
        selectedID = id
    }

    public mutating func reset() {
        selectedID = nil
    }
}

public enum WordIllustrationPalette: String, CaseIterable, Codable, Hashable {
    case sky
    case leaf
    case coral
    case sun
    case violet
    case aqua
    case rose
}

public struct WordIllustration: Identifiable, Equatable, Hashable {
    public let word: String
    public let glyph: String
    public let accessibilityLabel: String
    public let palette: WordIllustrationPalette

    public var id: String { word }

    public init(
        word: String,
        glyph: String,
        accessibilityLabel: String,
        palette: WordIllustrationPalette
    ) {
        self.word = word
        self.glyph = glyph
        self.accessibilityLabel = accessibilityLabel
        self.palette = palette
    }
}

public enum WordIllustrationProvider {
    public static func illustration(for text: String) -> WordIllustration? {
        let word = WordTextNormalizer.normalize(text)
        let value: (glyph: String, label: String, palette: WordIllustrationPalette)?

        switch word {
        case "grandma", "granny": value = ("👵", "祖母图示", .rose)
        case "grandpa", "grandad", "granddad": value = ("👴", "祖父图示", .sky)
        case "grandparent": value = ("🧓", "祖父或祖母图示", .violet)
        case "grandparents": value = ("👵👴", "祖父母图示", .violet)
        case "husband", "uncle", "father", "dad": value = ("👨", "男性家庭成员图示", .sky)
        case "wife", "aunt", "mother", "mum": value = ("👩", "女性家庭成员图示", .rose)
        case "cousin": value = ("🧑", "表亲或堂亲图示", .violet)
        case "nephew", "son", "brother", "brothers", "grandson": value = ("👦", "男孩家庭成员图示", .sky)
        case "niece", "daughter", "sister", "sisters", "granddaughter": value = ("👧", "女孩家庭成员图示", .rose)
        case "parent", "parents", "family": value = ("👨‍👩‍👧", "家庭图示", .violet)
        case "family tree": value = ("🌳", "家谱图示", .leaf)
        case "teenager": value = ("🧑", "青少年图示", .aqua)
        case "child": value = ("🧒", "儿童图示", .sun)
        case "children": value = ("🧒🧒", "儿童们图示", .sun)
        case "girl": value = ("👧", "女孩图示", .rose)
        case "boy": value = ("👦", "男孩图示", .sky)
        case "young", "youngest": value = ("🌱", "年幼图示", .leaf)
        case "older": value = ("🧓", "年长图示", .coral)
        case "friend", "friends", "best friend", "partner": value = ("🧑‍🤝‍🧑", "朋友图示", .aqua)
        case "funny": value = ("😄", "有趣图示", .sun)
        case "guitar": value = ("🎸", "吉他图示", .coral)
        case "band", "musician", "musical instrument": value = ("🎵", "音乐图示", .violet)
        case "party": value = ("🎉", "聚会图示", .rose)
        case "tonight": value = ("🌙", "今晚图示", .violet)
        case "called": value = ("📞", "打电话图示", .sky)
        case "live", "house", "home": value = ("🏠", "居住和房屋图示", .leaf)
        case "london": value = ("🇬🇧", "伦敦所在国家图示", .sky)
        case "poland": value = ("🇵🇱", "波兰图示", .rose)
        case "village": value = ("🏘️", "村庄图示", .leaf)
        case "town": value = ("🏙️", "城镇图示", .sky)
        case "north": value = ("🧭", "北方图示", .aqua)
        case "small": value = ("🤏", "小的图示", .sun)
        case "nearly": value = ("⏳", "接近完成图示", .coral)
        case "birthday": value = ("🎂", "生日图示", .rose)
        case "week": value = ("📅", "星期图示", .sky)
        case "lunch": value = ("🍱", "午餐图示", .coral)
        case "football", "match": value = ("⚽️", "足球比赛图示", .leaf)
        case "sport": value = ("🏃", "运动图示", .aqua)
        case "study": value = ("📚", "学习图示", .sky)
        case "hope": value = ("⭐️", "希望图示", .sun)
        case "university", "school": value = ("🏫", "学校图示", .sky)
        case "pet": value = ("🐾", "宠物图示", .coral)
        case "chair": value = ("🪑", "椅子图示", .coral)
        case "floor", "wall": value = ("🧱", "地面或墙面图示", .coral)
        case "fridge": value = ("🧊", "冰箱冷藏图示", .aqua)
        case "light": value = ("💡", "灯光图示", .sun)
        case "garage": value = ("🚗", "车库图示", .sky)
        case "table", "dining room": value = ("🍽️", "餐桌图示", .coral)
        case "desk": value = ("🖥️", "书桌图示", .sky)
        case "sofa", "living room": value = ("🛋️", "客厅沙发图示", .leaf)
        case "bed", "bedroom": value = ("🛏️", "床和卧室图示", .violet)
        case "door": value = ("🚪", "门图示", .coral)
        case "window": value = ("🪟", "窗户图示", .aqua)
        case "kitchen": value = ("🍳", "厨房图示", .coral)
        case "bathroom": value = ("🛁", "浴室图示", .aqua)
        case "garden": value = ("🌷", "花园图示", .leaf)
        case "cupboard": value = ("🗄️", "橱柜图示", .coral)
        case "mirror": value = ("🪞", "镜子图示", .aqua)
        case "clock": value = ("🕐", "时钟图示", .sky)
        case "picture": value = ("🖼️", "图片图示", .leaf)
        case "message": value = ("💬", "消息图示", .sky)
        case "note": value = ("📝", "笔记图示", .sun)
        case "guess": value = ("❓", "猜测图示", .coral)
        case "group": value = ("👥", "小组图示", .aqua)
        case "golden": value = ("🟨", "金色图示", .sun)
        case "grey", "gray": value = ("🎨", "灰色图示", .violet)
        case "listen": value = ("👂", "聆听图示", .aqua)
        case "teacher": value = ("👩‍🏫", "老师图示", .rose)
        case "student": value = ("🧑‍🎓", "学生图示", .sky)
        case "book": value = ("📘", "书本图示", .sky)
        case "apple": value = ("🍎", "苹果图示", .rose)
        case "banana": value = ("🍌", "香蕉图示", .sun)
        case "orange": value = ("🍊", "橙子图示", .coral)
        case "cat": value = ("🐱", "猫图示", .sun)
        case "dog": value = ("🐶", "狗图示", .coral)
        case "science": value = ("🧪", "科学实验图示", .aqua)
        case "robot": value = ("🤖", "机器人图示", .violet)
        case "jump": value = ("🤸", "跳跃图示", .leaf)
        case "rope": value = ("🪢", "绳子图示", .coral)
        case "hard-working": value = ("💪", "努力工作图示", .coral)
        case "doctor": value = ("🩺", "医生图示", .aqua)
        case "potato": value = ("🥔", "土豆图示", .coral)
        default: value = nil
        }

        guard let value else {
            return nil
        }
        return WordIllustration(
            word: word,
            glyph: value.glyph,
            accessibilityLabel: value.label,
            palette: value.palette
        )
    }
}

public enum PronunciationGuideProvider {
    public static func guide(for text: String) -> PronunciationGuide? {
        guides[WordTextNormalizer.normalize(text)]
    }

    public static var supportedWords: [String] {
        guides.keys.sorted()
    }

    private struct UnitSeed {
        let letters: String
        let americanIPA: String
        let britishIPA: String
        let kind: PronunciationUnitKind
    }

    private struct SyllableSeed {
        let text: String
        let americanIPA: String
        let britishIPA: String
    }

    private static func seed(_ text: String, _ americanIPA: String, _ britishIPA: String = "") -> SyllableSeed {
        SyllableSeed(text: text, americanIPA: americanIPA, britishIPA: britishIPA)
    }

    private static func unit(
        _ letters: String,
        _ americanIPA: String,
        _ britishIPA: String = "",
        _ kind: PronunciationUnitKind = .regular
    ) -> UnitSeed {
        UnitSeed(
            letters: letters,
            americanIPA: americanIPA,
            britishIPA: britishIPA.isEmpty ? americanIPA : britishIPA,
            kind: kind
        )
    }

    private static func group(_ letters: String, _ americanIPA: String, _ britishIPA: String = "") -> UnitSeed {
        unit(letters, americanIPA, britishIPA, .letterGroup)
    }

    private static func special(_ letters: String, _ americanIPA: String, _ britishIPA: String = "") -> UnitSeed {
        unit(letters, americanIPA, britishIPA, .irregular)
    }

    private static func silent(_ letters: String) -> UnitSeed {
        unit(letters, "", "", .silent)
    }

    private static func makeGuide(_ word: String, _ seeds: [SyllableSeed]) -> PronunciationGuide {
        PronunciationGuide(
            word: word,
            syllables: seeds.enumerated().map { index, seed in
                let wordUnits = phonicsUnits[word] ?? []
                let curatedUnits = wordUnits.indices.contains(index) ? wordUnits[index] : nil
                let unitSeeds = curatedUnits?.isEmpty == false
                    ? curatedUnits!
                    : [unit(seed.text, seed.americanIPA, seed.britishIPA, .irregular)]
                return PronunciationSyllable(
                    id: "\(word)-syllable-\(index)",
                    text: seed.text,
                    units: unitSeeds.enumerated().map { unitIndex, unitSeed in
                        PronunciationUnit(
                            id: "\(word)-unit-\(index)-\(unitIndex)",
                            letters: unitSeed.letters,
                            americanIPA: unitSeed.americanIPA,
                            britishIPA: unitSeed.britishIPA,
                            kind: unitSeed.kind
                        )
                    }
                )
            }
        )
    }

    private static let phonicsUnits: [String: [[UnitSeed]]] = [
        "granny": [[unit("g", "ɡ"), unit("r", "r"), unit("a", "æ"), unit("n", "n")], [special("ny", "i")]],
        "grandpa": [[unit("g", "ɡ"), unit("r", "r"), unit("a", "æ"), unit("n", "n"), unit("d", "d")], [unit("p", "p"), special("a", "ɑ", "ɑː")]],
        "granddad": [[unit("g", "ɡ"), unit("r", "r"), unit("a", "æ"), unit("n", "n"), unit("d", "d")], [unit("d", "d"), unit("a", "æ"), unit("d", "d")]],
        "grandparent": [[unit("g", "ɡ"), unit("r", "r"), unit("a", "æ"), unit("n", "n"), unit("d", "d")], [unit("p", "p"), group("ar", "er", "eə")], [special("e", "ə"), unit("n", "n"), unit("t", "t")]],
        "grandparents": [[unit("g", "ɡ"), unit("r", "r"), unit("a", "æ"), unit("n", "n"), unit("d", "d")], [unit("p", "p"), group("ar", "er", "eə")], [special("e", "ə"), unit("n", "n"), unit("t", "t"), unit("s", "s")]],
        "nephew": [[unit("n", "n"), unit("e", "e"), group("ph", "f")], [group("ew", "juː")]],
        "niece": [[unit("n", "n"), group("ie", "iː"), group("ce", "s")]],
        "sisters": [[unit("s", "s"), unit("i", "ɪ"), unit("s", "s")], [unit("t", "t"), group("er", "ɚ", "ə"), unit("s", "z")]],
        "brothers": [[unit("b", "b"), unit("r", "r"), special("o", "ʌ"), group("th", "ð")], [group("er", "ɚ", "ə"), unit("s", "z")]],
        "parent": [[unit("p", "p"), group("ar", "er", "eə")], [special("e", "ə"), unit("n", "n"), unit("t", "t")]],
        "parents": [[unit("p", "p"), group("ar", "er", "eə")], [special("e", "ə"), unit("n", "n"), unit("t", "t"), unit("s", "s")]],
        "family tree": [[unit("f", "f"), unit("a", "æ"), unit("m", "m")], [special("i", "ə")], [unit("l", "l"), special("y", "i")], [unit("t", "t"), unit("r", "r"), group("ee", "iː")]],
        "teenager": [[unit("t", "t"), group("ee", "iː"), unit("n", "n")], [special("a", "eɪ")], [special("g", "dʒ"), group("er", "ɚ", "ə")]],
        "child": [[group("ch", "tʃ"), special("i", "aɪ"), unit("l", "l"), unit("d", "d")]],
        "children": [[group("ch", "tʃ"), unit("i", "ɪ"), unit("l", "l")], [unit("d", "d"), unit("r", "r"), special("e", "ə"), unit("n", "n")]],
        "girl": [[unit("g", "ɡ"), group("ir", "ɝː", "ɜː"), unit("l", "l")]],
        "boy": [[unit("b", "b"), group("oy", "ɔɪ")]],
        "young": [[unit("y", "j"), special("ou", "ʌ"), group("ng", "ŋ")]],
        "youngest": [[unit("y", "j"), special("ou", "ʌ"), group("ng", "ŋɡ")], [special("e", "ə", "ɪ"), unit("s", "s"), unit("t", "t")]],
        "friend": [[unit("f", "f"), unit("r", "r"), special("ie", "e"), unit("n", "n"), unit("d", "d")]],
        "friends": [[unit("f", "f"), unit("r", "r"), special("ie", "e"), unit("n", "n"), unit("d", "d"), unit("s", "z")]],
        "best friend": [[unit("b", "b"), unit("e", "e"), unit("s", "s"), unit("t", "t")], [unit("f", "f"), unit("r", "r"), special("ie", "e"), unit("n", "n"), unit("d", "d")]],
        "funny": [[unit("f", "f"), unit("u", "ʌ"), unit("n", "n")], [special("ny", "i")]],
        "guitar": [[unit("g", "ɡ"), special("ui", "ɪ")], [unit("t", "t"), group("ar", "ɑːr", "ɑː")]],
        "band": [[unit("b", "b"), unit("a", "æ"), unit("n", "n"), unit("d", "d")]],
        "party": [[unit("p", "p"), group("ar", "ɑːr", "ɑː")], [unit("t", "t"), special("y", "i")]],
        "tonight": [[special("to", "tə")], [unit("n", "n"), group("igh", "aɪ"), unit("t", "t")]],
        "called": [[unit("c", "k"), group("all", "ɔːl"), special("ed", "d")]],
        "live": [[unit("l", "l"), unit("i", "ɪ"), unit("v", "v"), silent("e")]],
        "london": [[unit("l", "l"), special("o", "ʌ"), unit("n", "n")], [unit("d", "d"), special("o", "ə"), unit("n", "n")]],
        "mum": [[unit("m", "m"), unit("u", "ʌ"), unit("m", "m")]],
        "dad": [[unit("d", "d"), unit("a", "æ"), unit("d", "d")]],
        "musician": [[unit("m", "m"), special("u", "ju")], [special("s", "z"), unit("i", "ɪ")], [special("cian", "ʃən")]],
        "village": [[unit("v", "v"), unit("i", "ɪ"), unit("l", "l")], [silent("l"), special("a", "ɪ"), group("ge", "dʒ")]],
        "town": [[unit("t", "t"), group("ow", "aʊ"), unit("n", "n")]],
        "north": [[unit("n", "n"), group("or", "ɔːr", "ɔː"), group("th", "θ")]],
        "small": [[unit("s", "s"), unit("m", "m"), group("all", "ɔːl")]],
        "nearly": [[unit("n", "n"), group("ear", "ɪr", "ɪə")], [unit("l", "l"), special("y", "i")]],
        "older": [[special("o", "oʊ", "əʊ"), unit("l", "l"), unit("d", "d")], [group("er", "ɚ", "ə")]],
        "birthday": [[unit("b", "b"), group("ir", "ɝː", "ɜː"), group("th", "θ")], [unit("d", "d"), group("ay", "eɪ")]],
        "week": [[unit("w", "w"), group("ee", "iː"), unit("k", "k")]],
        "lunch": [[unit("l", "l"), unit("u", "ʌ"), unit("n", "n"), group("ch", "tʃ")]],
        "football": [[unit("f", "f"), group("oo", "ʊ"), unit("t", "t")], [unit("b", "b"), group("all", "ɔːl")]],
        "match": [[unit("m", "m"), unit("a", "æ"), group("tch", "tʃ")]],
        "study": [[unit("s", "s"), unit("t", "t"), unit("u", "ʌ"), unit("d", "d")], [special("y", "i")]],
        "hope": [[unit("h", "h"), special("o", "oʊ", "əʊ"), unit("p", "p"), silent("e")]],
        "sport": [[unit("s", "s"), unit("p", "p"), group("or", "ɔːr", "ɔː"), unit("t", "t")]],
        "poland": [[unit("p", "p"), special("o", "oʊ", "əʊ")], [unit("l", "l"), special("a", "ə"), unit("n", "n"), unit("d", "d")]],
        "chair": [[group("ch", "tʃ"), group("air", "er", "eə")]],
        "floor": [[unit("f", "f"), unit("l", "l"), group("oor", "ɔːr", "ɔː")]],
        "fridge": [[unit("f", "f"), unit("r", "r"), unit("i", "ɪ"), group("dge", "dʒ")]],
        "light": [[unit("l", "l"), group("igh", "aɪ"), unit("t", "t")]],
        "garage": [[unit("g", "ɡ"), special("a", "ə", "æ")], [unit("r", "r"), special("a", "ɑː"), group("ge", "ʒ")]],
        "table": [[unit("t", "t"), special("a", "eɪ")], [unit("b", "b"), group("le", "əl")]],
        "desk": [[unit("d", "d"), unit("e", "e"), unit("s", "s"), unit("k", "k")]],
        "sofa": [[unit("s", "s"), special("o", "oʊ", "əʊ")], [unit("f", "f"), special("a", "ə")]],
        "bed": [[unit("b", "b"), unit("e", "e"), unit("d", "d")]],
        "door": [[unit("d", "d"), group("oor", "ɔːr", "ɔː")]],
        "window": [[unit("w", "w"), unit("i", "ɪ"), unit("n", "n")], [unit("d", "d"), group("ow", "oʊ", "əʊ")]],
        "kitchen": [[unit("k", "k"), unit("i", "ɪ"), unit("t", "t")], [special("ch", "ʃ"), special("e", "ə"), unit("n", "n")]],
        "bathroom": [[unit("b", "b"), unit("a", "æ", "ɑː"), group("th", "θ")], [unit("r", "r"), group("oo", "uː"), unit("m", "m")]],
        "bedroom": [[unit("b", "b"), unit("e", "e"), unit("d", "d")], [unit("r", "r"), group("oo", "uː"), unit("m", "m")]],
        "living room": [[unit("l", "l"), unit("i", "ɪ"), unit("v", "v")], [unit("i", "ɪ"), group("ng", "ŋ")], [unit("r", "r"), group("oo", "uː"), unit("m", "m")]],
        "dining room": [[unit("d", "d"), special("i", "aɪ"), unit("n", "n")], [unit("i", "ɪ"), group("ng", "ŋ")], [unit("r", "r"), group("oo", "uː"), unit("m", "m")]],
        "house": [[unit("h", "h"), group("ou", "aʊ"), group("se", "s")]],
        "home": [[unit("h", "h"), special("o", "oʊ", "əʊ"), unit("m", "m"), silent("e")]],
        "wall": [[unit("w", "w"), group("all", "ɔːl")]],
        "garden": [[unit("g", "ɡ"), group("ar", "ɑːr", "ɑː")], [unit("d", "d"), special("e", "ə"), unit("n", "n")]],
        "cupboard": [[unit("c", "k"), unit("u", "ʌ"), silent("p")], [unit("b", "b"), special("oar", "ɚ", "ə"), unit("d", "d")]],
        "mirror": [[unit("m", "m"), unit("i", "ɪ"), unit("r", "r", "")], [unit("r", "r", ""), special("o", "ə"), unit("r", "r", "")]],
        "clock": [[unit("c", "k"), unit("l", "l"), unit("o", "ɑː", "ɒ"), group("ck", "k")]],
        "picture": [[unit("p", "p"), unit("i", "ɪ"), unit("c", "k")], [special("t", "tʃ"), group("ure", "ɚ", "ə")]],
        "message": [[unit("m", "m"), unit("e", "e"), unit("s", "s")], [silent("s"), special("a", "ɪ"), group("ge", "dʒ")]],
        "note": [[unit("n", "n"), special("o", "oʊ", "əʊ"), unit("t", "t"), silent("e")]],
        "guess": [[unit("g", "ɡ"), silent("u"), unit("e", "e"), group("ss", "s")]],
        "group": [[unit("g", "ɡ"), unit("r", "r"), group("ou", "uː"), unit("p", "p")]],
        "golden": [[unit("g", "ɡ"), special("o", "oʊ", "əʊ"), unit("l", "l"), unit("d", "d")], [special("e", "ə"), unit("n", "n")]],
        "partner": [[unit("p", "p"), group("ar", "ɑːr", "ɑː"), unit("t", "t")], [unit("n", "n"), group("er", "ɚ", "ə")]],
        "grey": [[unit("g", "ɡ"), unit("r", "r"), group("ey", "eɪ")]],
        "gray": [[unit("g", "ɡ"), unit("r", "r"), group("ay", "eɪ")]],
        "listen": [[unit("l", "l"), unit("i", "ɪ"), unit("s", "s")], [silent("t"), special("e", "ə"), unit("n", "n")]],
        "father": [[unit("f", "f"), special("a", "ɑ", "ɑː")], [group("th", "ð"), group("er", "ɚ", "ə")]],
        "mother": [[unit("m", "m"), special("o", "ʌ")], [group("th", "ð"), group("er", "ɚ", "ə")]],
        "family": [[unit("f", "f"), unit("a", "æ"), unit("m", "m")], [special("i", "ə")], [unit("l", "l"), special("y", "i")]],
        "school": [[group("sch", "sk"), group("oo", "uː"), unit("l", "l")]],
        "teacher": [[unit("t", "t"), group("ea", "iː"), group("ch", "tʃ")], [group("er", "ɚ", "ə")]],
        "student": [[unit("s", "s"), unit("t", "t"), special("u", "uː", "juː")], [unit("d", "d"), special("e", "ə"), unit("n", "n"), unit("t", "t")]],
        "book": [[unit("b", "b"), group("oo", "ʊ"), unit("k", "k")]],
        "apple": [[unit("a", "æ"), unit("p", "p")], [unit("p", "p"), group("le", "əl")]],
        "banana": [[unit("b", "b"), special("a", "ə")], [unit("n", "n"), unit("a", "æ", "ɑː")], [unit("n", "n"), special("a", "ə")]],
        "orange": [[special("o", "ɔr", "ɒ"), unit("r", "", "", .silent)], [special("a", "ɪ"), group("nge", "ndʒ")]],
        "cat": [[unit("c", "k"), unit("a", "æ"), unit("t", "t")]],
        "dog": [[unit("d", "d"), unit("o", "ɔː", "ɒ"), unit("g", "ɡ")]],
        "grandma": [
            [unit("g", "ɡ"), unit("r", "r"), unit("a", "æ"), unit("n", "n"), unit("d", "", "", .silent)],
            [unit("m", "m"), unit("a", "ɑ", "ɑː", .irregular)]
        ],
        "grandad": [
            [unit("g", "ɡ"), unit("r", "r"), unit("a", "æ"), unit("n", "n"), unit("d", "d")],
            [unit("a", "æ"), unit("d", "d")]
        ],
        "husband": [
            [unit("h", "h"), unit("u", "ʌ"), unit("s", "z", "", .irregular)],
            [unit("b", "b"), unit("a", "ə", "", .irregular), unit("n", "n"), unit("d", "d")]
        ],
        "wife": [[
            unit("w", "w"), unit("i", "aɪ", "", .irregular), unit("f", "f"), unit("e", "", "", .silent)
        ]],
        "uncle": [
            [unit("u", "ʌ"), unit("n", "ŋ", "", .irregular)],
            [unit("c", "k"), unit("le", "əl", "", .letterGroup)]
        ],
        "aunt": [[
            unit("au", "æ", "ɑː", .letterGroup), unit("n", "n"), unit("t", "t")
        ]],
        "cousin": [
            [unit("c", "k"), unit("ou", "ʌ", "", .irregular), unit("s", "z", "", .irregular)],
            [unit("i", "ə", "", .irregular), unit("n", "n")]
        ],
        "son": [[unit("s", "s"), unit("o", "ʌ", "", .irregular), unit("n", "n")]],
        "daughter": [
            [unit("d", "d"), unit("augh", "ɔ", "ɔː", .letterGroup)],
            [unit("t", "t"), unit("er", "ɚ", "ə", .letterGroup)]
        ],
        "sister": [
            [unit("s", "s"), unit("i", "ɪ"), unit("s", "s")],
            [unit("t", "t"), unit("er", "ɚ", "ə", .letterGroup)]
        ],
        "brother": [
            [unit("b", "b"), unit("r", "r"), unit("o", "ʌ", "", .irregular), unit("th", "ð", "", .letterGroup)],
            [unit("er", "ɚ", "ə", .letterGroup)]
        ],
        "grandson": [
            [unit("g", "ɡ"), unit("r", "r"), unit("a", "æ"), unit("n", "n"), unit("d", "", "", .silent)],
            [unit("s", "s"), unit("o", "ʌ", "", .irregular), unit("n", "n")]
        ],
        "granddaughter": [
            [unit("g", "ɡ"), unit("r", "r"), unit("a", "æ"), unit("n", "n"), unit("d", "", "", .silent)],
            [unit("d", "d"), unit("augh", "ɔ", "ɔː", .letterGroup)],
            [unit("t", "t"), unit("er", "ɚ", "ə", .letterGroup)]
        ],
        "university": [
            [unit("u", "ju", "juː", .irregular)],
            [unit("n", "n"), unit("i", "ə", "ɪ", .irregular)],
            [unit("v", "v"), unit("er", "ɝ", "ɜː", .letterGroup)],
            [unit("s", "s"), unit("i", "ə", "", .irregular)],
            [unit("t", "t"), unit("y", "i", "", .irregular)]
        ],
        "pet": [[unit("p", "p"), unit("e", "e"), unit("t", "t")]],
        "musical instrument": [
            [unit("m", "m"), unit("u", "ju", "juː", .irregular)],
            [unit("s", "z", "", .irregular), unit("i", "ɪ")],
            [unit("c", "k"), unit("a", "ə", "", .irregular), unit("l", "l")],
            [unit("i", "ɪ"), unit("n", "n")],
            [unit("s", "s"), unit("t", "t"), unit("r", "r"), unit("u", "ə", "", .irregular)],
            [unit("m", "m"), unit("e", "e"), unit("n", "n"), unit("t", "t")]
        ],
        "science": [
            [unit("sc", "s", "", .letterGroup), unit("i", "aɪ", "", .irregular)],
            [unit("e", "ə", "", .irregular), unit("n", "n"), unit("ce", "s", "", .letterGroup)]
        ],
        "robot": [
            [unit("r", "r"), unit("o", "oʊ", "əʊ", .irregular)],
            [unit("b", "b"), unit("o", "ɑ", "ɒ"), unit("t", "t")]
        ],
        "jump": [[unit("j", "dʒ", "", .irregular), unit("u", "ʌ"), unit("m", "m"), unit("p", "p")]],
        "rope": [[unit("r", "r"), unit("o", "oʊ", "əʊ", .irregular), unit("p", "p"), unit("e", "", "", .silent)]],
        "hard-working": [
            [unit("h", "h"), unit("ar", "ɑr", "ɑː", .letterGroup), unit("d", "d"), unit("-", "", "", .silent)],
            [unit("w", "w"), unit("or", "ɝ", "ɜː", .letterGroup), unit("k", "k")],
            [unit("i", "ɪ"), unit("ng", "ŋ", "", .letterGroup)]
        ]
    ]

    private static let doctor = PronunciationGuide(
        word: "doctor",
        syllables: [
            PronunciationSyllable(id: "doctor-syllable-0", text: "doc", units: [
                PronunciationUnit(id: "doctor-d", letters: "d", americanIPA: "d"),
                PronunciationUnit(id: "doctor-o", letters: "o", americanIPA: "ɑ", britishIPA: "ɒ"),
                PronunciationUnit(id: "doctor-c", letters: "c", americanIPA: "k")
            ]),
            PronunciationSyllable(id: "doctor-syllable-1", text: "tor", units: [
                PronunciationUnit(id: "doctor-t", letters: "t", americanIPA: "t"),
                PronunciationUnit(id: "doctor-or", letters: "or", americanIPA: "ɚ", britishIPA: "ə")
            ])
        ]
    )

    private static let potato = PronunciationGuide(
        word: "potato",
        syllables: [
            PronunciationSyllable(id: "potato-syllable-0", text: "po", units: [
                PronunciationUnit(id: "potato-p", letters: "p", americanIPA: "p"),
                PronunciationUnit(id: "potato-o-0", letters: "o", americanIPA: "ə")
            ]),
            PronunciationSyllable(id: "potato-syllable-1", text: "ta", units: [
                PronunciationUnit(id: "potato-t-0", letters: "t", americanIPA: "t"),
                PronunciationUnit(id: "potato-a", letters: "a", americanIPA: "eɪ")
            ]),
            PronunciationSyllable(id: "potato-syllable-2", text: "to", units: [
                PronunciationUnit(id: "potato-t-1", letters: "t", americanIPA: "t"),
                PronunciationUnit(id: "potato-o-1", letters: "o", americanIPA: "oʊ", britishIPA: "əʊ")
            ])
        ]
    )

    private static let guides: [String: PronunciationGuide] = {
        let entries: [(String, [SyllableSeed])] = [
            ("grandma", [seed("grand", "ɡræn"), seed("ma", "mɑ", "mɑː")]),
            ("granny", [seed("gran", "ɡræn"), seed("ny", "i")]),
            ("grandpa", [seed("grand", "ɡrænd"), seed("pa", "pɑ", "pɑː")]),
            ("grandad", [seed("grand", "ɡrænd"), seed("ad", "æd")]),
            ("granddad", [seed("grand", "ɡrænd"), seed("dad", "dæd")]),
            ("grandparent", [seed("grand", "ɡrænd"), seed("par", "per", "peə"), seed("ent", "ənt")]),
            ("grandparents", [seed("grand", "ɡrænd"), seed("par", "per", "peə"), seed("ents", "ənts")]),
            ("husband", [seed("hus", "hʌz"), seed("band", "bənd")]),
            ("wife", [seed("wife", "waɪf")]),
            ("uncle", [seed("un", "ʌŋ"), seed("cle", "kəl")]),
            ("aunt", [seed("aunt", "ænt", "ɑːnt")]),
            ("cousin", [seed("cous", "kʌz"), seed("in", "ən")]),
            ("nephew", [seed("neph", "nef"), seed("ew", "juː")]),
            ("niece", [seed("niece", "niːs")]),
            ("son", [seed("son", "sʌn")]),
            ("daughter", [seed("daugh", "dɔ", "dɔː"), seed("ter", "tɚ", "tə")]),
            ("sister", [seed("sis", "sɪs"), seed("ter", "tɚ", "tə")]),
            ("sisters", [seed("sis", "sɪs"), seed("ters", "tɚz", "təz")]),
            ("brother", [seed("broth", "brʌð"), seed("er", "ɚ", "ə")]),
            ("brothers", [seed("broth", "brʌð"), seed("ers", "ɚz", "əz")]),
            ("parent", [seed("par", "per", "peə"), seed("ent", "ənt")]),
            ("parents", [seed("par", "per", "peə"), seed("ents", "ənts")]),
            ("family tree", [seed("fam", "fæm"), seed("i", "ə"), seed("ly", "li"), seed("tree", "triː")]),
            ("teenager", [seed("teen", "tiːn"), seed("a", "eɪ"), seed("ger", "dʒɚ", "dʒə")]),
            ("child", [seed("child", "tʃaɪld")]),
            ("children", [seed("chil", "tʃɪl"), seed("dren", "drən")]),
            ("girl", [seed("girl", "ɡɝːl", "ɡɜːl")]),
            ("boy", [seed("boy", "bɔɪ")]),
            ("young", [seed("young", "jʌŋ")]),
            ("youngest", [seed("young", "jʌŋɡ"), seed("est", "əst", "ɪst")]),
            ("friend", [seed("friend", "frend")]),
            ("friends", [seed("friends", "frendz")]),
            ("best friend", [seed("best", "best"), seed("friend", "frend")]),
            ("funny", [seed("fun", "fʌn"), seed("ny", "i")]),
            ("guitar", [seed("gui", "ɡɪ"), seed("tar", "tɑːr", "tɑː")]),
            ("band", [seed("band", "bænd")]),
            ("party", [seed("par", "pɑːr", "pɑː"), seed("ty", "ti")]),
            ("tonight", [seed("to", "tə"), seed("night", "naɪt")]),
            ("called", [seed("called", "kɔːld")]),
            ("live", [seed("live", "lɪv")]),
            ("london", [seed("lon", "lʌn"), seed("don", "dən")]),
            ("mum", [seed("mum", "mʌm")]),
            ("dad", [seed("dad", "dæd")]),
            ("musician", [seed("mu", "mju"), seed("si", "zɪ"), seed("cian", "ʃən")]),
            ("village", [seed("vil", "vɪl"), seed("lage", "ɪdʒ")]),
            ("town", [seed("town", "taʊn")]),
            ("north", [seed("north", "nɔːrθ", "nɔːθ")]),
            ("small", [seed("small", "smɔːl")]),
            ("nearly", [seed("near", "nɪr", "nɪə"), seed("ly", "li")]),
            ("older", [seed("old", "oʊld", "əʊld"), seed("er", "ɚ", "ə")]),
            ("birthday", [seed("birth", "bɝːθ", "bɜːθ"), seed("day", "deɪ")]),
            ("week", [seed("week", "wiːk")]),
            ("lunch", [seed("lunch", "lʌntʃ")]),
            ("football", [seed("foot", "fʊt"), seed("ball", "bɔːl")]),
            ("match", [seed("match", "mætʃ")]),
            ("study", [seed("stud", "stʌd"), seed("y", "i")]),
            ("hope", [seed("hope", "hoʊp", "həʊp")]),
            ("sport", [seed("sport", "spɔːrt", "spɔːt")]),
            ("poland", [seed("po", "poʊ", "pəʊ"), seed("land", "lənd")]),
            ("grandson", [seed("grand", "ɡræn"), seed("son", "sʌn")]),
            ("granddaughter", [seed("grand", "ɡræn"), seed("daugh", "dɔ", "dɔː"), seed("ter", "tɚ", "tə")]),
            ("university", [seed("u", "ju"), seed("ni", "nə", "nɪ"), seed("ver", "vɝ", "vɜː"), seed("si", "sə"), seed("ty", "ti")]),
            ("pet", [seed("pet", "pet")]),
            ("musical instrument", [seed("mu", "mju"), seed("si", "zɪ"), seed("cal", "kəl"), seed("in", "ɪn"), seed("stru", "strə"), seed("ment", "mənt")]),
            ("chair", [seed("chair", "tʃer", "tʃeə")]),
            ("floor", [seed("floor", "flɔːr", "flɔː")]),
            ("fridge", [seed("fridge", "frɪdʒ")]),
            ("light", [seed("light", "laɪt")]),
            ("garage", [seed("ga", "ɡə", "ɡæ"), seed("rage", "rɑːʒ")]),
            ("table", [seed("ta", "teɪ"), seed("ble", "bəl")]),
            ("desk", [seed("desk", "desk")]),
            ("sofa", [seed("so", "soʊ", "səʊ"), seed("fa", "fə")]),
            ("bed", [seed("bed", "bed")]),
            ("door", [seed("door", "dɔːr", "dɔː")]),
            ("window", [seed("win", "wɪn"), seed("dow", "doʊ", "dəʊ")]),
            ("kitchen", [seed("kit", "kɪt"), seed("chen", "ʃən")]),
            ("bathroom", [seed("bath", "bæθ", "bɑːθ"), seed("room", "ruːm")]),
            ("bedroom", [seed("bed", "bed"), seed("room", "ruːm")]),
            ("living room", [seed("liv", "lɪv"), seed("ing", "ɪŋ"), seed("room", "ruːm")]),
            ("dining room", [seed("din", "daɪn"), seed("ing", "ɪŋ"), seed("room", "ruːm")]),
            ("house", [seed("house", "haʊs")]),
            ("home", [seed("home", "hoʊm", "həʊm")]),
            ("wall", [seed("wall", "wɔːl")]),
            ("garden", [seed("gar", "ɡɑːr", "ɡɑː"), seed("den", "dən")]),
            ("cupboard", [seed("cup", "kʌ"), seed("board", "bɚd", "bəd")]),
            ("mirror", [seed("mir", "mɪr", "mɪ"), seed("ror", "ɚ", "rə")]),
            ("clock", [seed("clock", "klɑːk", "klɒk")]),
            ("picture", [seed("pic", "pɪk"), seed("ture", "tʃɚ", "tʃə")]),
            ("message", [seed("mes", "mes"), seed("sage", "ɪdʒ")]),
            ("note", [seed("note", "noʊt", "nəʊt")]),
            ("guess", [seed("guess", "ɡes")]),
            ("group", [seed("group", "ɡruːp")]),
            ("golden", [seed("gold", "ɡoʊld", "ɡəʊld"), seed("en", "ən")]),
            ("partner", [seed("part", "pɑːrt", "pɑːt"), seed("ner", "nɚ", "nə")]),
            ("grey", [seed("grey", "ɡreɪ")]),
            ("gray", [seed("gray", "ɡreɪ")]),
            ("listen", [seed("lis", "lɪs"), seed("ten", "ən")]),
            ("father", [seed("fa", "fɑ", "fɑː"), seed("ther", "ðɚ", "ðə")]),
            ("mother", [seed("mo", "mʌ"), seed("ther", "ðɚ", "ðə")]),
            ("family", [seed("fam", "fæm"), seed("i", "ə"), seed("ly", "li")]),
            ("school", [seed("school", "skuːl")]),
            ("teacher", [seed("teach", "tiːtʃ"), seed("er", "ɚ", "ə")]),
            ("student", [seed("stu", "stuː", "stjuː"), seed("dent", "dənt")]),
            ("book", [seed("book", "bʊk")]),
            ("apple", [seed("ap", "æp"), seed("ple", "əl")]),
            ("banana", [seed("ba", "bə"), seed("na", "næ", "nɑː"), seed("na", "nə")]),
            ("orange", [seed("or", "ɔr", "ɒ"), seed("ange", "ɪndʒ")]),
            ("cat", [seed("cat", "kæt")]),
            ("dog", [seed("dog", "dɔːɡ", "dɒɡ")]),
            ("science", [seed("sci", "saɪ"), seed("ence", "əns")]),
            ("robot", [seed("ro", "roʊ", "rəʊ"), seed("bot", "bɑt", "bɒt")]),
            ("jump", [seed("jump", "dʒʌmp")]),
            ("rope", [seed("rope", "roʊp", "rəʊp")]),
            ("hard-working", [seed("hard-", "hɑrd", "hɑːd"), seed("work", "wɝk", "wɜːk"), seed("ing", "ɪŋ")])
        ]

        var result = Dictionary(uniqueKeysWithValues: entries.map { ($0.0, makeGuide($0.0, $0.1)) })
        result[doctor.word] = doctor
        result[potato.word] = potato
        return result
    }()
}

public struct SpellingPiece: Identifiable, Equatable, Hashable {
    public let id: UUID
    public let text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

public struct SpellingPuzzle: Equatable {
    public let answer: String
    public private(set) var availablePieces: [SpellingPiece]
    public private(set) var selectedPieces: [SpellingPiece]

    private let initialPieces: [SpellingPiece]
    private let joinsWithSpaces: Bool

    public init(answer: String, preferredChunks: [String]) {
        self.answer = WordTextNormalizer.displayText(for: answer)
        let words = self.answer.split(whereSeparator: \Character.isWhitespace).map(String.init)
        let rawPieces: [String]

        if words.count > 1 {
            rawPieces = words
            joinsWithSpaces = true
        } else if !preferredChunks.isEmpty,
                  WordTextNormalizer.normalize(preferredChunks.joined()) == WordTextNormalizer.normalize(self.answer) {
            rawPieces = preferredChunks
            joinsWithSpaces = false
        } else {
            rawPieces = self.answer.map(String.init)
            joinsWithSpaces = false
        }

        let pieces = rawPieces.map { SpellingPiece(text: $0) }
        let shuffled = Self.shuffledDifferently(pieces)
        initialPieces = shuffled
        availablePieces = shuffled
        selectedPieces = []
    }

    public var composedAnswer: String {
        selectedPieces.map(\.text).joined(separator: joinsWithSpaces ? " " : "")
    }

    public var isCorrect: Bool {
        WordTextNormalizer.normalize(composedAnswer) == WordTextNormalizer.normalize(answer)
    }

    public var isComplete: Bool {
        availablePieces.isEmpty
    }

    public mutating func select(pieceID: SpellingPiece.ID) {
        guard let index = availablePieces.firstIndex(where: { $0.id == pieceID }) else {
            return
        }
        selectedPieces.append(availablePieces.remove(at: index))
    }

    public mutating func undoLastSelection() {
        guard let piece = selectedPieces.popLast() else {
            return
        }
        availablePieces.append(piece)
    }

    public mutating func reset() {
        selectedPieces = []
        availablePieces = initialPieces
    }

    private static func shuffledDifferently(_ pieces: [SpellingPiece]) -> [SpellingPiece] {
        guard pieces.count > 1 else {
            return pieces
        }
        let originalIDs = pieces.map(\.id)
        var shuffled = pieces.shuffled()
        if shuffled.map(\.id) == originalIDs {
            shuffled.append(shuffled.removeFirst())
        }
        return shuffled
    }
}
