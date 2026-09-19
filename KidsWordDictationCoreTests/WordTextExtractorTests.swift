import XCTest
@testable import KidsWordDictationCore

final class WordTextExtractorTests: XCTestCase {
    func testExtractsOnlyEnglishWordsFromPrintedVocabularyList() {
        let text = """
        U1 单词
        1. grandma n. （外）祖母；奶奶；外婆
        2. grandad n. 爷爷；外公
        3. husband n. 丈夫
        4. wife n. 妻子；太太；夫人；已婚妇女
        5. uncle n. 舅父；叔父；伯父；姑父；姨父
        6. aunt n. 姑母；姨母；伯母；婶母；舅母
        7. cousin n. 堂兄弟姐妹；表兄弟姐妹
        8. son n. 儿子
        9. daughter n. 女儿
        10. sister n. 姐；妹
        11. brother n. （同父母的）兄，弟
        12. grandson n. 孙子；外孙
        13. granddaughter n. （外）孙女
        14. university n. 大学，（综合性）大学；高等学府
        15. pet n. 宠物
        16. musical instrument 乐器
        """

        let words = WordTextExtractor.extractWords(from: text).map(\.text)

        XCTAssertEqual(words, [
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
        ])
    }

    func testExtractsChineseTranslationsFromScannedLines() {
        let text = """
        1. grandma n. （外）祖母；奶奶；外婆
        16. musical instrument 乐器
        """

        let words = WordTextExtractor.extractWords(from: text)

        XCTAssertEqual(words.map(\.text), ["grandma", "musical instrument"])
        XCTAssertEqual(words.map(\.translation), ["(外)祖母；奶奶；外婆", "乐器"])
    }

    func testIgnoresPartOfSpeechOnlyLinesAndDeduplicatesCaseInsensitively() {
        let text = """
        n. 名词
        1. Grandma n. 奶奶
        2. grandma n. 外婆
        adj. 形容词
        """

        let words = WordTextExtractor.extractWords(from: text)

        XCTAssertEqual(words.map(\.text), ["Grandma"])
        XCTAssertEqual(words.first?.normalizedText, "grandma")
    }

    func testFiltersOcrNoiseFragmentsFromVocabularyList() {
        let text = """
        16. musical instrument 乐器
        FX
        *Xx: 1Hx: #ix: #x
        JL
        H tet
        """

        let words = WordTextExtractor.extractWords(from: text)

        XCTAssertEqual(words.map(\.text), ["musical instrument"])
    }

    func testWordItemAddsKnownPhoneticByDefault() {
        let word = WordItem(text: "wife")

        XCTAssertEqual(word.phonetic, "/waɪf/")
        XCTAssertEqual(word.britishPhonetic, "/waɪf/")
    }

    func testWordMetadataProviderMarksMissingUnknownWords() {
        let word = WordItem(text: "zzunknown")

        XCTAssertEqual(word.missingMetadataLabels, ["美式音标", "英式音标", "中文释义"])
        XCTAssertFalse(word.hasCompleteRequiredMetadata)
    }

    func testWordItemBackfillsMissingMetadataWhenDecodingOldData() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "text": "chair",
          "normalizedText": "chair",
          "phonetic": "",
          "britishPhonetic": "",
          "translation": "",
          "sentence": ""
        }
        """.data(using: .utf8)!

        let word = try JSONDecoder().decode(WordItem.self, from: json)

        XCTAssertEqual(word.phonetic, "/tʃer/")
        XCTAssertEqual(word.britishPhonetic, "/tʃeə/")
        XCTAssertEqual(word.translation, "椅子")
        XCTAssertEqual(word.sentence, "Please sit on the chair.")
        XCTAssertTrue(word.hasCompleteRequiredMetadata)
    }

    func testKetFamilyWordsAddPhoneticsTranslationsAndSentences() {
        let words = WordTextExtractor.extractWords(from: """
        family tree
        teenager
        child
        """)

        XCTAssertEqual(words.map(\.text), ["family tree", "teenager", "child"])
        XCTAssertEqual(words.map(\.translation), ["家谱；家庭关系图", "青少年", "儿童；孩子"])
        XCTAssertEqual(words.map(\.phonetic), ["/ˈfæməli triː/", "/ˈtiːneɪdʒɚ/", "/tʃaɪld/"])
        XCTAssertEqual(words.map(\.britishPhonetic), ["/ˈfæməli triː/", "/ˈtiːneɪdʒə/", "/tʃaɪld/"])
        XCTAssertEqual(words.map(\.sentence), [
            "This is my family tree.",
            "My sister is a teenager.",
            "The child is reading a book."
        ])
    }

    func testKetExtendedWordsAddMetadata() {
        let words = WordTextExtractor.extractWords(from: """
        granny
        nephew
        niece
        musician
        village
        """)

        XCTAssertEqual(words.map(\.text), ["granny", "nephew", "niece", "musician", "village"])
        XCTAssertEqual(words.map(\.translation), ["奶奶；外婆；祖母", "侄子；外甥", "侄女；外甥女", "音乐家", "村庄"])
        XCTAssertEqual(words.map(\.phonetic), ["/ˈɡræni/", "/ˈnefjuː/", "/niːs/", "/mjuˈzɪʃən/", "/ˈvɪlɪdʒ/"])
        XCTAssertEqual(words.map(\.britishPhonetic), ["/ˈɡræni/", "/ˈnefjuː/", "/niːs/", "/mjuˈzɪʃən/", "/ˈvɪlɪdʒ/"])
        XCTAssertEqual(words.map(\.sentence), [
            "My granny lives in a small town.",
            "My nephew is seven years old.",
            "My niece likes music.",
            "My mum is a musician.",
            "They live in a small village."
        ])
    }

    func testKetHomeWordsAddMetadata() {
        let words = WordTextExtractor.extractWords(from: """
        chair
        floor
        fridge
        light
        garage
        """)

        XCTAssertEqual(words.map(\.text), ["chair", "floor", "fridge", "light", "garage"])
        XCTAssertEqual(words.map(\.translation), ["椅子", "地板；楼层", "冰箱", "灯；光", "车库"])
        XCTAssertEqual(words.map(\.phonetic), ["/tʃer/", "/flɔːr/", "/frɪdʒ/", "/laɪt/", "/ɡəˈrɑːʒ/"])
        XCTAssertEqual(words.map(\.britishPhonetic), ["/tʃeə/", "/flɔː/", "/frɪdʒ/", "/laɪt/", "/ˈɡærɑːʒ/"])
        XCTAssertEqual(words.map(\.sentence), [
            "Please sit on the chair.",
            "The bag is on the floor.",
            "There is milk in the fridge.",
            "Please turn on the light.",
            "The car is in the garage."
        ])
    }
}
