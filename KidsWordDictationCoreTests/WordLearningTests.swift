import XCTest
@testable import KidsWordDictationCore

final class WordLearningTests: XCTestCase {
    func testKnownWordsReturnCuratedPronunciationGuides() {
        let doctor = PronunciationGuideProvider.guide(for: "Doctor")
        XCTAssertEqual(doctor?.syllables.map(\.text), ["doc", "tor"])
        XCTAssertEqual(doctor?.units.map(\.letters), ["d", "o", "c", "t", "or"])
        XCTAssertEqual(doctor?.units.map(\.americanIPA), ["d", "ɑ", "k", "t", "ɚ"])

        let potato = PronunciationGuideProvider.guide(for: "potato")
        XCTAssertEqual(potato?.syllables.map(\.text), ["po", "ta", "to"])
        XCTAssertEqual(potato?.spellingChunks, ["po", "ta", "to"])
        XCTAssertEqual(potato?.units.map(\.letters), ["p", "o", "t", "a", "t", "o"])
        XCTAssertEqual(potato?.units.map(\.americanIPA), ["p", "ə", "t", "eɪ", "t", "oʊ"])
    }

    func testUnknownWordDoesNotReceiveGuessedPronunciationGuide() {
        XCTAssertNil(PronunciationGuideProvider.guide(for: "codexophone"))
    }

    func testExampleWordsIncludeOfflineLearningMetadata() {
        let doctor = WordItem(text: "doctor")
        XCTAssertEqual(doctor.phonetic, "/ˈdɑːktɚ/")
        XCTAssertEqual(doctor.britishPhonetic, "/ˈdɒktə/")
        XCTAssertEqual(doctor.translation, "医生；博士")
        XCTAssertFalse(doctor.sentence.isEmpty)

        let potato = WordItem(text: "potato")
        XCTAssertEqual(potato.translation, "土豆；马铃薯")
        XCTAssertFalse(potato.phonetic.isEmpty)
        XCTAssertFalse(potato.britishPhonetic.isEmpty)
    }

    func testSpellingPuzzleShufflesAndPreservesDuplicatePieces() {
        let puzzle = SpellingPuzzle(answer: "letter", preferredChunks: [])

        XCTAssertEqual(puzzle.availablePieces.map(\.text).sorted(), ["e", "e", "l", "r", "t", "t"])
        XCTAssertNotEqual(puzzle.availablePieces.map(\.text), ["l", "e", "t", "t", "e", "r"])
    }

    func testSpellingPuzzleSupportsSelectionUndoResetAndValidation() throws {
        var puzzle = SpellingPuzzle(answer: "doctor", preferredChunks: ["doc", "tor"])
        let doc = try XCTUnwrap(puzzle.availablePieces.first { $0.text == "doc" })
        let tor = try XCTUnwrap(puzzle.availablePieces.first { $0.text == "tor" })

        puzzle.select(pieceID: doc.id)
        puzzle.select(pieceID: tor.id)
        XCTAssertEqual(puzzle.composedAnswer, "doctor")
        XCTAssertTrue(puzzle.isCorrect)

        puzzle.undoLastSelection()
        XCTAssertFalse(puzzle.isCorrect)
        XCTAssertEqual(puzzle.selectedPieces.map(\.text), ["doc"])

        puzzle.reset()
        XCTAssertTrue(puzzle.selectedPieces.isEmpty)
        XCTAssertEqual(puzzle.availablePieces.count, 2)
    }

    func testMultiWordPhraseUsesWordPiecesAndIgnoresExtraWhitespace() {
        var puzzle = SpellingPuzzle(answer: "musical   instrument", preferredChunks: [])
        let musical = puzzle.availablePieces.first { $0.text == "musical" }!
        let instrument = puzzle.availablePieces.first { $0.text == "instrument" }!

        puzzle.select(pieceID: musical.id)
        puzzle.select(pieceID: instrument.id)

        XCTAssertEqual(puzzle.composedAnswer, "musical instrument")
        XCTAssertTrue(puzzle.isCorrect)
    }
}
