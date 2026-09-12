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
}
