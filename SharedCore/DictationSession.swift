import Foundation

public struct AnswerResult: Equatable {
    public var item: WordItem
    public var submittedAnswer: String
    public var isCorrect: Bool
    public var expectedAnswer: String
}

public struct DictationSession: Equatable {
    public private(set) var queue: [WordItem]
    public private(set) var currentIndex: Int
    public private(set) var correctCount: Int
    public private(set) var answeredCount: Int
    public private(set) var lastResult: AnswerResult?
    public private(set) var mode: DictationMode

    private var submittedCurrentAnswer: Bool

    public init(words: [WordItem], mode: DictationMode = .shuffled) {
        var generator = SystemRandomNumberGenerator()
        self.init(words: words, mode: mode, randomNumberGenerator: &generator)
    }

    public init<RNG: RandomNumberGenerator>(words: [WordItem], mode: DictationMode = .shuffled, randomNumberGenerator: inout RNG) {
        let uniqueWords = DictationSession.deduplicated(words)
        var queue = uniqueWords
        if mode == .shuffled {
            queue = uniqueWords.shuffled(using: &randomNumberGenerator)
            if queue == uniqueWords, queue.count > 1 {
                queue.swapAt(0, queue.count - 1)
            }
        }

        self.queue = queue
        self.currentIndex = 0
        self.correctCount = 0
        self.answeredCount = 0
        self.lastResult = nil
        self.mode = mode
        self.submittedCurrentAnswer = false
    }

    public var currentItem: WordItem? {
        guard queue.indices.contains(currentIndex) else {
            return nil
        }
        return queue[currentIndex]
    }

    public var totalCount: Int {
        queue.count
    }

    public var isFinished: Bool {
        currentIndex >= queue.count
    }

    @discardableResult
    public mutating func submit(answer: String) -> AnswerResult? {
        guard let item = currentItem else {
            return nil
        }

        let normalizedAnswer = WordTextNormalizer.normalize(answer)
        let isCorrect = normalizedAnswer == item.normalizedText
        let result = AnswerResult(
            item: item,
            submittedAnswer: WordTextNormalizer.displayText(for: answer),
            isCorrect: isCorrect,
            expectedAnswer: item.text
        )

        if !submittedCurrentAnswer {
            answeredCount += 1
            if isCorrect {
                correctCount += 1
            }
        }

        submittedCurrentAnswer = true
        lastResult = result
        return result
    }

    public mutating func moveNext() {
        currentIndex += 1
        lastResult = nil
        submittedCurrentAnswer = false
    }

    public mutating func move(to index: Int) {
        guard queue.indices.contains(index) else {
            return
        }
        currentIndex = index
        lastResult = nil
        submittedCurrentAnswer = false
    }

    public mutating func restart() {
        var generator = SystemRandomNumberGenerator()
        self = DictationSession(words: queue, mode: mode, randomNumberGenerator: &generator)
    }

    private static func deduplicated(_ words: [WordItem]) -> [WordItem] {
        var seen = Set<String>()
        return words.filter { word in
            !word.normalizedText.isEmpty && seen.insert(word.normalizedText).inserted
        }
    }
}
