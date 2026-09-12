import XCTest
@testable import KidsWordDictationCore

final class WordListStoreTests: XCTestCase {
    func testPersistsWordListsAsJSON() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = try WordListStore(fileURL: temporaryDirectory.appendingPathComponent("word-lists.json"))
        let lists = [
            WordList(title: "U1", createdAt: Date(timeIntervalSince1970: 1), words: [
                WordItem(text: "grandma"),
                WordItem(text: "musical instrument")
            ])
        ]

        try store.save(lists)

        XCTAssertEqual(try store.load(), lists)
    }
}
