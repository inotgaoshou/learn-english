import Foundation

public struct PronunciationUnit: Identifiable, Equatable, Hashable {
    public let id: String
    public let letters: String
    public let americanIPA: String
    public let britishIPA: String

    public init(id: String = UUID().uuidString, letters: String, americanIPA: String, britishIPA: String = "") {
        self.id = id
        self.letters = letters
        self.americanIPA = americanIPA
        self.britishIPA = britishIPA.isEmpty ? americanIPA : britishIPA
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
}

public enum PronunciationGuideProvider {
    public static func guide(for text: String) -> PronunciationGuide? {
        guides[WordTextNormalizer.normalize(text)]
    }

    private struct SyllableSeed {
        let text: String
        let americanIPA: String
        let britishIPA: String
    }

    private static func seed(_ text: String, _ americanIPA: String, _ britishIPA: String = "") -> SyllableSeed {
        SyllableSeed(text: text, americanIPA: americanIPA, britishIPA: britishIPA)
    }

    private static func makeGuide(_ word: String, _ seeds: [SyllableSeed]) -> PronunciationGuide {
        PronunciationGuide(
            word: word,
            syllables: seeds.enumerated().map { index, seed in
                PronunciationSyllable(
                    id: "\(word)-syllable-\(index)",
                    text: seed.text,
                    units: [
                        PronunciationUnit(
                            id: "\(word)-unit-\(index)",
                            letters: seed.text,
                            americanIPA: seed.americanIPA,
                            britishIPA: seed.britishIPA
                        )
                    ]
                )
            }
        )
    }

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
            ("youngest", [seed("young", "jʌŋ"), seed("est", "ɡəst", "ɡɪst")]),
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
            ("golden", [seed("gold", "ɡoʊl", "ɡəʊl"), seed("en", "dən")]),
            ("partner", [seed("part", "pɑːrt", "pɑːt"), seed("ner", "nɚ", "nə")]),
            ("grey", [seed("grey", "ɡreɪ")]),
            ("gray", [seed("gray", "ɡreɪ")]),
            ("listen", [seed("lis", "lɪs"), seed("ten", "ən")]),
            ("father", [seed("fa", "fɑ", "fɑː"), seed("ther", "ðɚ", "ðə")]),
            ("mother", [seed("mo", "mʌ"), seed("ther", "ðɚ", "ðə")]),
            ("family", [seed("fam", "fæm"), seed("i", "ə"), seed("ly", "li")]),
            ("school", [seed("school", "skuːl")]),
            ("teacher", [seed("teach", "tiːtʃ"), seed("er", "ɚ", "ə")]),
            ("student", [seed("stu", "stu", "stjuː"), seed("dent", "dənt")]),
            ("book", [seed("book", "bʊk")]),
            ("apple", [seed("ap", "æp"), seed("ple", "əl")]),
            ("banana", [seed("ba", "bə"), seed("na", "næ", "nɑː"), seed("na", "nə")]),
            ("orange", [seed("or", "ɔr", "ɒ"), seed("ange", "ɪndʒ")]),
            ("cat", [seed("cat", "kæt")]),
            ("dog", [seed("dog", "dɔːɡ", "dɒɡ")])
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
