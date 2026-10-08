import XCTest
@testable import KidsWordDictationCore

final class WordLearningTests: XCTestCase {
    func testLearningStagesUseFiveStepOrder() {
        XCTAssertEqual(LearningStage.allCases, [.learn, .read, .select, .spell, .write])
    }

    func testOfflineGuidesHaveCuratedIllustrations() throws {
        for word in PronunciationGuideProvider.supportedWords {
            let illustration = try XCTUnwrap(
                WordIllustrationProvider.illustration(for: word),
                "Missing illustration for \(word)"
            )
            XCTAssertFalse(illustration.glyph.isEmpty, word)
            XCTAssertFalse(illustration.accessibilityLabel.isEmpty, word)
        }
    }

    func testIllustrationLookupNormalizesCaseAndRejectsUnknownWords() {
        XCTAssertEqual(WordIllustrationProvider.illustration(for: "  APPLE  ")?.glyph, "🍎")
        XCTAssertNil(WordIllustrationProvider.illustration(for: "codexophone"))
    }

    func testLegacyRemoteImageFieldIsIgnoredWhenDecodingWordItem() throws {
        let id = UUID()
        let json = #"""
        {
          "id": "\#(id.uuidString)",
          "text": "doctor",
          "normalizedText": "doctor",
          "phonetic": "/ˈdɑːktɚ/",
          "britishPhonetic": "/ˈdɒktə/",
          "translation": "医生；博士",
          "sentence": "The doctor helps sick people.",
          "sentenceTranslation": "医生帮助生病的人。",
          "image": {
            "id": "legacy",
            "thumbnailURL": "https://example.invalid/legacy.jpg"
          }
        }
        """#

        let decoded = try JSONDecoder().decode(WordItem.self, from: Data(json.utf8))
        let encoded = try JSONEncoder().encode(decoded)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.text, "doctor")
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("\"image\""))
    }

    func testKnownWordsReturnCuratedPronunciationGuides() {
        let doctor = PronunciationGuideProvider.guide(for: "Doctor")
        XCTAssertEqual(doctor?.syllables.map(\.text), ["doc", "tor"])
        XCTAssertEqual(doctor?.units.map(\.letters), ["d", "o", "c", "t", "or"])
        XCTAssertEqual(doctor?.units.map(\.americanIPA), ["d", "ɑ", "k", "t", "ɚ"])
        XCTAssertEqual(doctor?.spellingPieces, ["d", "o", "c", "t", "or"])

        let potato = PronunciationGuideProvider.guide(for: "potato")
        XCTAssertEqual(potato?.syllables.map(\.text), ["po", "ta", "to"])
        XCTAssertEqual(potato?.spellingChunks, ["po", "ta", "to"])
        XCTAssertEqual(potato?.spellingPieces, ["p", "o", "t", "a", "t", "o"])
        XCTAssertEqual(potato?.units.map(\.letters), ["p", "o", "t", "a", "t", "o"])
        XCTAssertEqual(potato?.units.map(\.americanIPA), ["p", "ə", "t", "eɪ", "t", "oʊ"])
    }

    func testAllOfflineGuidesHaveCompleteSyllableAndPhonicsCoverage() throws {
        XCTAssertEqual(PronunciationGuideProvider.supportedWords.count, 116)

        for word in PronunciationGuideProvider.supportedWords {
            let guide = try XCTUnwrap(PronunciationGuideProvider.guide(for: word), word)
            let syllableText = WordTextNormalizer.normalize(guide.syllables.map(\.text).joined())
            let expectedWord = WordTextNormalizer.normalize(word).replacingOccurrences(of: " ", with: "")
            XCTAssertEqual(syllableText, expectedWord, word)
            XCTAssertTrue(guide.hasReliablePhonics, word)

            let ids = guide.units.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, word)

            for syllable in guide.syllables {
                XCTAssertEqual(
                    WordTextNormalizer.normalize(syllable.units.map(\.letters).joined()),
                    WordTextNormalizer.normalize(syllable.text),
                    "\(word): \(syllable.text)"
                )
                XCTAssertTrue(
                    syllable.units.allSatisfy { $0.isSilent || (!$0.americanIPA.isEmpty && !$0.britishIPA.isEmpty) },
                    "\(word): \(syllable.text)"
                )
            }
        }
    }

    func testScienceUsesSyllablesAndDetailedPhonicsFromReferenceFlow() throws {
        let science = try XCTUnwrap(PronunciationGuideProvider.guide(for: "science"))

        XCTAssertEqual(science.syllables.map(\.text), ["sci", "ence"])
        XCTAssertEqual(science.units.map(\.letters), ["sc", "i", "e", "n", "ce"])
        XCTAssertEqual(science.units.map(\.americanIPA), ["s", "aɪ", "ə", "n", "s"])
        XCTAssertEqual(WordItem(text: "science").translation, "科学")
    }

    func testSilentAndGroupedUnitsAreExplicitlyMarked() throws {
        let wife = try XCTUnwrap(PronunciationGuideProvider.guide(for: "wife"))
        XCTAssertEqual(wife.units.last?.letters, "e")
        XCTAssertEqual(wife.units.last?.kind, .silent)

        let aunt = try XCTUnwrap(PronunciationGuideProvider.guide(for: "aunt"))
        XCTAssertEqual(aunt.units.first?.letters, "au")
        XCTAssertEqual(aunt.units.first?.kind, .letterGroup)
    }

    func testSelectionExerciseUsesUniqueUnitOptionsAndChecksAnswer() throws {
        let words = ["science", "robot", "jump", "rope", "science"].map { WordItem(text: $0) }
        var exercise = SelectionExercise(answer: words[0], candidates: words)

        XCTAssertEqual(exercise.options.count, 4)
        XCTAssertEqual(Set(exercise.options.map(\.normalizedText)).count, 4)
        XCTAssertTrue(exercise.options.contains { $0.normalizedText == "science" })

        let wrong = try XCTUnwrap(exercise.options.first { $0.normalizedText != "science" })
        exercise.select(wrong.id)
        XCTAssertFalse(exercise.isCorrect)

        let correct = try XCTUnwrap(exercise.options.first { $0.normalizedText == "science" })
        exercise.select(correct.id)
        XCTAssertTrue(exercise.isCorrect)
    }

    func testUnknownWordDoesNotReceiveGuessedPronunciationGuide() {
        XCTAssertNil(PronunciationGuideProvider.guide(for: "codexophone"))
    }

    func testSingleUnitGuideFallsBackToLettersForSpelling() {
        let wife = PronunciationGuideProvider.guide(for: "wife")

        XCTAssertEqual(wife?.spellingPieces, ["w", "i", "f", "e"])
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

    func testUnknownWordFallsBackToLettersForSpelling() {
        let puzzle = SpellingPuzzle(answer: "codex", preferredChunks: [])

        XCTAssertEqual(puzzle.availablePieces.map(\.text).sorted(), ["c", "d", "e", "o", "x"])
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

    func testMultiWordGuideKeepsSpacesInColoredSyllableDisplay() throws {
        let guide = try XCTUnwrap(PronunciationGuideProvider.guide(for: "musical instrument"))

        XCTAssertEqual(guide.displaySyllableTexts, ["mu", "si", "cal", " in", "stru", "ment"])
        XCTAssertEqual(guide.displaySyllableTexts.joined(), "musical instrument")
    }

    func testLearningProgressKeepsStagesIndependentPerWord() {
        let firstID = UUID()
        let secondID = UUID()
        var progress = LearningProgress()

        progress.markComplete(.spell, for: firstID)
        progress.markComplete(.learn, for: firstID)
        progress.markComplete(.read, for: secondID)

        XCTAssertEqual(progress.completedStages(for: firstID), [.learn, .spell])
        XCTAssertEqual(progress.completedStages(for: secondID), [.read])
        XCTAssertTrue(progress.completedStages(for: UUID()).isEmpty)
    }
}
