import XCTest
@testable import KidsWordDictationCore

final class DictationSessionTests: XCTestCase {
    func testSessionShufflesWordsAndDoesNotRepeatWithinRound() {
        let words = ["grandma", "grandad", "husband", "wife"].map { WordItem(text: $0) }
        var generator = SeededRandomNumberGenerator(seed: 1)

        let session = DictationSession(words: words, mode: .shuffled, randomNumberGenerator: &generator)

        XCTAssertNotEqual(session.queue.map(\.text), words.map(\.text))
        XCTAssertEqual(Set(session.queue.map(\.normalizedText)).count, words.count)
        XCTAssertEqual(session.totalCount, words.count)
    }

    func testOrderedSessionKeepsUnitOrder() {
        let words = ["grandma", "grandad", "husband", "wife"].map { WordItem(text: $0) }
        var generator = SeededRandomNumberGenerator(seed: 1)

        let session = DictationSession(words: words, mode: .ordered, randomNumberGenerator: &generator)

        XCTAssertEqual(session.queue.map(\.text), words.map(\.text))
    }

    func testAnswerCheckingIgnoresCaseAndExtraSpacesForPhrases() {
        let words = [WordItem(text: "musical instrument")]
        var session = DictationSession(words: words)

        let result = session.submit(answer: "Musical   Instrument")

        XCTAssertEqual(result?.isCorrect, true)
        XCTAssertEqual(session.correctCount, 1)
        XCTAssertEqual(session.answeredCount, 1)
    }

    func testMoveNextFinishesAfterLastWord() {
        var session = DictationSession(words: [WordItem(text: "pet")])

        XCTAssertFalse(session.isFinished)
        session.moveNext()

        XCTAssertTrue(session.isFinished)
    }

    func testMoveToJumpsWithinTemporaryQueue() {
        var session = DictationSession(words: ["grandma", "grandad", "husband"].map { WordItem(text: $0) }, mode: .ordered)

        session.move(to: 2)

        XCTAssertEqual(session.currentItem?.text, "husband")
    }
}

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
