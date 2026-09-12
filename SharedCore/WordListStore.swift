import Foundation

public final class WordListStore {
    public enum StoreError: Error {
        case documentsDirectoryUnavailable
    }

    public let fileURL: URL

    public init(fileURL: URL? = nil) throws {
        if let fileURL {
            self.fileURL = fileURL
        } else if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            self.fileURL = documentsDirectory.appendingPathComponent("word-lists.json")
        } else {
            throw StoreError.documentsDirectoryUnavailable
        }
    }

    public func load() throws -> [WordList] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([WordList].self, from: data)
    }

    public func save(_ wordLists: [WordList]) throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(wordLists)
        try data.write(to: fileURL, options: [.atomic])
    }
}
