import XCTest
@testable import KidsWordDictationCore

final class WordMetadataServicesTests: XCTestCase {
    func testScreenshotWordsHaveCompleteOfflineMetadata() {
        let words = ["stair", "roof", "lift", "start", "invitation", "worry"].map { WordItem(text: $0) }

        XCTAssertTrue(words.allSatisfy(\.hasCompleteRequiredMetadata))
        XCTAssertEqual(words.first?.translation, "楼梯；梯级")
        XCTAssertEqual(words.last?.phonetic, "/ˈwɝːi/")
        XCTAssertEqual(words.last?.britishPhonetic, "/ˈwʌri/")
    }

    func testDictionaryParserUsesGenericIPAForBothAccentsAndFindsExample() throws {
        let data = Data(#"""
        [{
          "phonetics": [{"text": "təˈmeɪtoʊ", "audio": ""}],
          "meanings": [{"definitions": [{"definition": "x", "example": "This is a tomato."}]}]
        }]
        """#.utf8)

        let metadata = try OnlineWordMetadataService.metadata(from: data)

        XCTAssertEqual(metadata.americanPhonetic, "/təˈmeɪtoʊ/")
        XCTAssertEqual(metadata.britishPhonetic, "/təˈmeɪtoʊ/")
        XCTAssertEqual(metadata.sentence, "This is a tomato.")
    }

    func testDictionaryParserSeparatesAmericanAndBritishAudioRecords() throws {
        let data = Data(#"""
        [{
          "phonetics": [
            {"text": "/ster/", "audio": "https://example.com/stair-us.mp3"},
            {"text": "/steə/", "audio": "https://example.com/stair-uk.mp3"}
          ],
          "meanings": []
        }]
        """#.utf8)

        let metadata = try OnlineWordMetadataService.metadata(from: data)

        XCTAssertEqual(metadata.americanPhonetic, "/ster/")
        XCTAssertEqual(metadata.britishPhonetic, "/steə/")
    }

    func testDictionaryParserUsesTopLevelPhoneticWhenRecordsAreEmpty() throws {
        let data = Data(#"""
        [{"phonetic":"/ɡes/","phonetics":[],"meanings":[]}]
        """#.utf8)

        let metadata = try OnlineWordMetadataService.metadata(from: data)

        XCTAssertEqual(metadata.americanPhonetic, "/ɡes/")
        XCTAssertEqual(metadata.britishPhonetic, "/ɡes/")
    }

    func testOnlineLookupSendsOnlyPercentEncodedNormalizedWord() async throws {
        let baseURL = URL(string: "https://dictionary.example/entries/")!
        let recorder = RequestRecorder()
        let service = OnlineWordMetadataService(baseURL: baseURL) { request in
            recorder.record(request)
            return (
                Data(#"[{"phonetics":[{"text":"/ˈmjuːzɪkəl/","audio":""}],"meanings":[]}]"#.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }

        _ = try await service.lookup("  Musical Instrument  ")

        XCTAssertEqual(recorder.lastURL?.absoluteString, "https://dictionary.example/entries/musical%20instrument")
        XCTAssertNil(recorder.lastRequest?.httpBody)
    }

    func testOnlineLookupRejectsNonEnglishTextWithoutSendingRequest() async {
        let recorder = RequestRecorder()
        let service = makeService(recorder: recorder)

        do {
            _ = try await service.lookup("单词和整页文章")
            XCTFail("Expected invalid word error")
        } catch let error as OnlineWordMetadataError {
            XCTAssertEqual(error, .invalidWord)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(recorder.count, 0)
    }

    func testCoordinatorDoesNotCallNetworkWhenDisabled() async {
        let recorder = RequestRecorder()
        let service = makeService(recorder: recorder)
        let cacheURL = temporaryURL("disabled")
        let coordinator = WordMetadataCoordinator(
            service: service,
            cache: WordMetadataCache(fileURL: cacheURL)
        )

        let result = await coordinator.resolve(text: "codexophone", allowNetwork: false)

        XCTAssertEqual(recorder.count, 0)
        XCTAssertEqual(result.source, .offline)
        XCTAssertFalse(result.missingLabels.isEmpty)
    }

    func testCoordinatorCachesSuccessfulLookup() async {
        let recorder = RequestRecorder()
        let service = makeService(recorder: recorder)
        let coordinator = WordMetadataCoordinator(
            service: service,
            cache: WordMetadataCache(fileURL: temporaryURL("success"))
        )

        let first = await coordinator.resolve(text: "codexophone", allowNetwork: true)
        let second = await coordinator.resolve(text: "codexophone", allowNetwork: true)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(first.source, .dictionaryAPI)
        XCTAssertEqual(second.source, .cache)
        XCTAssertEqual(second.metadata.americanPhonetic, "/ˈkoʊdeksəfoʊn/")
    }

    func testResolvedMetadataDoesNotOverwriteManualValues() {
        var manual = WordMetadata(
            americanPhonetic: "/manual/",
            translation: "手动释义",
            sentence: "A parent wrote this example."
        )
        manual.fillMissing(from: WordMetadata(
            americanPhonetic: "/online-us/",
            britishPhonetic: "/online-uk/",
            translation: "在线释义",
            sentence: "An online example.",
            sentenceTranslation: "在线例句。"
        ))

        XCTAssertEqual(manual.americanPhonetic, "/manual/")
        XCTAssertEqual(manual.britishPhonetic, "/online-uk/")
        XCTAssertEqual(manual.translation, "手动释义")
        XCTAssertEqual(manual.sentence, "A parent wrote this example.")
        XCTAssertTrue(manual.sentenceTranslation.isEmpty)
    }

    func testRecentFailurePreventsRepeatedRequestsUntilRefresh() async {
        let recorder = RequestRecorder()
        let baseURL = URL(string: "https://dictionary.example/entries/")!
        let service = OnlineWordMetadataService(baseURL: baseURL) { request in
            recorder.record(request)
            return (
                Data("{}".utf8),
                HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            )
        }
        let coordinator = WordMetadataCoordinator(
            service: service,
            cache: WordMetadataCache(fileURL: temporaryURL("failure"))
        )

        _ = await coordinator.resolve(text: "notaword", allowNetwork: true)
        _ = await coordinator.resolve(text: "notaword", allowNetwork: true)
        _ = await coordinator.resolve(text: "notaword", allowNetwork: true, refresh: true)

        XCTAssertEqual(recorder.count, 2)
    }

    func testFailureCacheExpiresAfterTwentyFourHours() async {
        let clock = MutableClock(now: Date(timeIntervalSince1970: 1_000))
        let cache = WordMetadataCache(
            fileURL: temporaryURL("failure-expiry"),
            now: { clock.now }
        )

        await cache.storeFailure(for: "notaword")
        let isInitiallyCached = await cache.hasRecentFailure(for: "notaword")
        clock.now = clock.now.addingTimeInterval(24 * 60 * 60 + 1)
        let isExpired = await cache.hasRecentFailure(for: "notaword")

        XCTAssertTrue(isInitiallyCached)
        XCTAssertFalse(isExpired)
    }

    func testCoordinatorReportsTimeoutWithoutBlockingMetadata() async {
        let baseURL = URL(string: "https://dictionary.example/entries/")!
        let service = OnlineWordMetadataService(baseURL: baseURL) { _ in
            throw URLError(.timedOut)
        }
        let coordinator = WordMetadataCoordinator(
            service: service,
            cache: WordMetadataCache(fileURL: temporaryURL("timeout"))
        )

        let result = await coordinator.resolve(text: "codexophone", allowNetwork: true)

        XCTAssertEqual(result.source, .dictionaryAPI)
        XCTAssertEqual(result.failureReason, "在线词典请求超时")
        XCTAssertFalse(result.missingLabels.isEmpty)
    }

    func testDictionaryServiceReportsRateLimit() async {
        let baseURL = URL(string: "https://dictionary.example/entries/")!
        let service = OnlineWordMetadataService(baseURL: baseURL) { request in
            (
                Data(),
                HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            )
        }

        do {
            _ = try await service.lookup("word")
            XCTFail("Expected HTTP status error")
        } catch let error as OnlineWordMetadataError {
            XCTAssertEqual(error, .httpStatus(429))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDictionaryServiceRejectsMalformedJSON() async {
        let baseURL = URL(string: "https://dictionary.example/entries/")!
        let service = OnlineWordMetadataService(baseURL: baseURL) { request in
            (
                Data("not-json".utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }

        do {
            _ = try await service.lookup("word")
            XCTFail("Expected invalid response error")
        } catch let error as OnlineWordMetadataError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSpellingSuggestionSelectsWorryForOCRTypo() {
        XCTAssertEqual(
            SpellingSuggestionSelector.bestSuggestion(
                for: "woryy",
                candidates: ["work", "world", "wordy", "worry", "sorry"]
            ),
            "worry"
        )
    }

    private func makeService(recorder: RequestRecorder) -> OnlineWordMetadataService {
        let baseURL = URL(string: "https://dictionary.example/entries/")!
        return OnlineWordMetadataService(baseURL: baseURL) { request in
            recorder.record(request)
            return (
                Data(#"[{"phonetics":[{"text":"/ˈkoʊdeksəfoʊn/","audio":""}],"meanings":[]}]"#.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
    }

    private func temporaryURL(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("word-metadata-tests-\(UUID().uuidString)-\(suffix).json")
    }
}

private final class RequestRecorder {
    private let lock = NSLock()
    private(set) var count = 0
    private(set) var lastRequest: URLRequest?

    var lastURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return lastRequest?.url
    }

    func record(_ request: URLRequest) {
        lock.lock()
        count += 1
        lastRequest = request
        lock.unlock()
    }
}

private final class MutableClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
