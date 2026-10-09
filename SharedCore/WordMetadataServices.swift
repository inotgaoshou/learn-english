import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OnlineCompletionSettings {
    public static let storageKey = "KidsWordDictation.onlineMetadataCompletionEnabled"
}

public enum WordMetadataSource: String, Codable, Equatable, Sendable {
    case offline
    case cache
    case dictionaryAPI
    case appleTranslation
    case manual
}

public struct WordMetadataResolution: Equatable, Sendable {
    public let metadata: WordMetadata
    public let source: WordMetadataSource
    public let missingLabels: [String]
    public let failureReason: String?

    public init(
        metadata: WordMetadata,
        source: WordMetadataSource,
        missingLabels: [String]? = nil,
        failureReason: String? = nil
    ) {
        self.metadata = metadata
        self.source = source
        self.missingLabels = missingLabels ?? metadata.missingRequiredLabels
        self.failureReason = failureReason
    }
}

public enum OnlineWordMetadataError: LocalizedError, Equatable {
    case invalidWord
    case invalidResponse
    case notFound
    case httpStatus(Int)
    case noUsableMetadata

    public var errorDescription: String? {
        switch self {
        case .invalidWord:
            return "单词格式无效"
        case .invalidResponse:
            return "在线词典返回了无法识别的数据"
        case .notFound:
            return "在线词典未收录这个单词"
        case let .httpStatus(code):
            return "在线词典暂不可用（HTTP \(code)）"
        case .noUsableMetadata:
            return "在线词典没有可用的音标或例句"
        }
    }
}

public struct OnlineWordMetadataService {
    public typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)

    private let dataLoader: DataLoader
    private let baseURL: URL

    public init(
        baseURL: URL = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/")!,
        timeout: TimeInterval = 12,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        if let session {
            self.dataLoader = { request in try await session.data(for: request) }
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = timeout
            configuration.timeoutIntervalForResource = timeout
            configuration.waitsForConnectivity = false
            let configuredSession = URLSession(configuration: configuration)
            self.dataLoader = { request in try await configuredSession.data(for: request) }
        }
    }

    public init(baseURL: URL, dataLoader: @escaping DataLoader) {
        self.baseURL = baseURL
        self.dataLoader = dataLoader
    }

    public func lookup(_ text: String) async throws -> WordMetadata {
        let word = WordTextNormalizer.normalize(text)
        guard isSafeDictionaryQuery(word) else {
            throw OnlineWordMetadataError.invalidWord
        }

        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard let encodedWord = word.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: encodedWord, relativeTo: baseURL)?.absoluteURL else {
            throw OnlineWordMetadataError.invalidWord
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await dataLoader(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnlineWordMetadataError.invalidResponse
        }
        if httpResponse.statusCode == 404 {
            throw OnlineWordMetadataError.notFound
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw OnlineWordMetadataError.httpStatus(httpResponse.statusCode)
        }

        let entries: [DictionaryEntry]
        do {
            entries = try JSONDecoder().decode([DictionaryEntry].self, from: data)
        } catch {
            throw OnlineWordMetadataError.invalidResponse
        }

        let metadata = Self.metadata(from: entries)
        guard !metadata.americanPhonetic.isEmpty
                || !metadata.britishPhonetic.isEmpty
                || !metadata.sentence.isEmpty else {
            throw OnlineWordMetadataError.noUsableMetadata
        }
        return metadata
    }

    public static func metadata(from data: Data) throws -> WordMetadata {
        let entries = try JSONDecoder().decode([DictionaryEntry].self, from: data)
        return metadata(from: entries)
    }

    private static func metadata(from entries: [DictionaryEntry]) -> WordMetadata {
        let phonetics = entries.flatMap(\.phonetics)
        let american = firstPhonetic(in: phonetics, accent: .american)
        let british = firstPhonetic(in: phonetics, accent: .british)
        let generic = phonetics
            .compactMap { normalizedIPA($0.text) }
            .first
            ?? entries.compactMap { normalizedIPA($0.phonetic) }.first
        let sentence = entries
            .flatMap(\.meanings)
            .flatMap(\.definitions)
            .compactMap { definition -> String? in
                guard let example = definition.example else { return nil }
                let clean = WordTextNormalizer.displayText(for: example)
                return clean.isEmpty ? nil : clean
            }
            .first ?? ""

        return WordMetadata(
            americanPhonetic: american ?? (british == nil ? generic ?? "" : ""),
            britishPhonetic: british ?? (american == nil ? generic ?? "" : ""),
            sentence: sentence
        )
    }

    private enum Accent {
        case american
        case british
    }

    private static func firstPhonetic(in values: [DictionaryPhonetic], accent: Accent) -> String? {
        values.first { value in
            let audio = value.audio.lowercased()
            switch accent {
            case .american:
                return audio.contains("-us") || audio.contains("_us") || audio.contains("/us/")
            case .british:
                return audio.contains("-uk") || audio.contains("_uk") || audio.contains("/uk/")
            }
        }.flatMap { normalizedIPA($0.text) }
    }

    private static func normalizedIPA(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if (clean.hasPrefix("/") && clean.hasSuffix("/"))
            || (clean.hasPrefix("[") && clean.hasSuffix("]")) {
            return clean
        }
        return "/\(clean)/"
    }

    private func isSafeDictionaryQuery(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 80 else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 97 && scalar.value <= 122)
                || scalar == " "
                || scalar == "-"
                || scalar == "'"
        }
    }
}

private struct DictionaryEntry: Decodable {
    let phonetic: String?
    let phonetics: [DictionaryPhonetic]
    let meanings: [DictionaryMeaning]

    enum CodingKeys: String, CodingKey {
        case phonetic
        case phonetics
        case meanings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic)
        phonetics = try container.decodeIfPresent([DictionaryPhonetic].self, forKey: .phonetics) ?? []
        meanings = try container.decodeIfPresent([DictionaryMeaning].self, forKey: .meanings) ?? []
    }
}

private struct DictionaryPhonetic: Decodable {
    let text: String?
    let audio: String

    enum CodingKeys: String, CodingKey {
        case text
        case audio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        audio = try container.decodeIfPresent(String.self, forKey: .audio) ?? ""
    }
}

private struct DictionaryMeaning: Decodable {
    let definitions: [DictionaryDefinition]
}

private struct DictionaryDefinition: Decodable {
    let example: String?
}

public actor WordMetadataCache {
    private struct Entry: Codable {
        var metadata: WordMetadata?
        var failedAt: Date?
    }

    private let fileURL: URL
    private let now: () -> Date
    private var entries: [String: Entry]?

    public init(fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = directory.appendingPathComponent("word-metadata-cache.json")
        }
        self.now = now
    }

    public func metadata(for text: String) -> WordMetadata? {
        loadIfNeeded()
        return entries?[WordTextNormalizer.normalize(text)]?.metadata
    }

    public func hasRecentFailure(for text: String, lifetime: TimeInterval = 24 * 60 * 60) -> Bool {
        loadIfNeeded()
        guard let failedAt = entries?[WordTextNormalizer.normalize(text)]?.failedAt else {
            return false
        }
        return now().timeIntervalSince(failedAt) < lifetime
    }

    public func store(_ metadata: WordMetadata, for text: String) {
        loadIfNeeded()
        let key = WordTextNormalizer.normalize(text)
        guard !key.isEmpty else { return }
        entries?[key] = Entry(metadata: metadata, failedAt: nil)
        persist()
    }

    public func storeFailure(for text: String) {
        loadIfNeeded()
        let key = WordTextNormalizer.normalize(text)
        guard !key.isEmpty else { return }
        let retainedMetadata = entries?[key]?.metadata
        entries?[key] = Entry(metadata: retainedMetadata, failedAt: now())
        persist()
    }

    public func clearFailure(for text: String) {
        loadIfNeeded()
        let key = WordTextNormalizer.normalize(text)
        guard var entry = entries?[key] else { return }
        entry.failedAt = nil
        entries?[key] = entry
        persist()
    }

    private func loadIfNeeded() {
        guard entries == nil else { return }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            entries = [:]
            return
        }
        entries = decoded
    }

    private func persist() {
        guard let entries,
              let data = try? JSONEncoder().encode(entries) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Cache failures must never block the learning workflow.
        }
    }
}

public actor WordMetadataCoordinator {
    public static let shared = WordMetadataCoordinator()

    private let service: OnlineWordMetadataService
    private let cache: WordMetadataCache

    public init(
        service: OnlineWordMetadataService = OnlineWordMetadataService(),
        cache: WordMetadataCache = WordMetadataCache()
    ) {
        self.service = service
        self.cache = cache
    }

    public func resolve(
        text: String,
        allowNetwork: Bool,
        refresh: Bool = false
    ) async -> WordMetadataResolution {
        let word = WordTextNormalizer.normalize(text)
        let offline = WordMetadataProvider.metadata(for: word)
        guard !word.isEmpty else {
            return WordMetadataResolution(
                metadata: offline,
                source: .offline,
                failureReason: OnlineWordMetadataError.invalidWord.localizedDescription
            )
        }

        if offline.hasCompleteRequiredMetadata && !offline.sentence.isEmpty {
            return WordMetadataResolution(metadata: offline, source: .offline)
        }

        var resolved = offline
        if !refresh, let cached = await cache.metadata(for: word) {
            resolved.fillMissing(from: cached)
            return WordMetadataResolution(metadata: resolved, source: .cache)
        }

        guard allowNetwork else {
            return WordMetadataResolution(metadata: resolved, source: .offline)
        }
        if !refresh, await cache.hasRecentFailure(for: word) {
            return WordMetadataResolution(
                metadata: resolved,
                source: .cache,
                failureReason: "在线词典近期未能补全，可稍后重新查询"
            )
        }

        do {
            let online = try await service.lookup(word)
            await cache.store(online, for: word)
            resolved.fillMissing(from: online)
            return WordMetadataResolution(metadata: resolved, source: .dictionaryAPI)
        } catch {
            await cache.storeFailure(for: word)
            return WordMetadataResolution(
                metadata: resolved,
                source: .dictionaryAPI,
                failureReason: Self.failureReason(for: error)
            )
        }
    }

    private static func failureReason(for error: Error) -> String {
        if let onlineError = error as? OnlineWordMetadataError {
            return onlineError.localizedDescription
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "在线词典请求超时"
            case .notConnectedToInternet:
                return "当前无网络连接"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "暂时无法连接在线词典"
            case .networkConnectionLost:
                return "网络连接已中断"
            default:
                return "在线词典请求失败（\(urlError.code.rawValue)）"
            }
        }
        return "在线词典请求失败"
    }

    public func resolveMany(
        texts: [String],
        allowNetwork: Bool,
        refresh: Bool = false,
        maximumConcurrentRequests: Int = 3
    ) async -> [String: WordMetadataResolution] {
        let uniqueWords = Array(Set(texts.map(WordTextNormalizer.normalize).filter { !$0.isEmpty })).sorted()
        var results: [String: WordMetadataResolution] = [:]
        let batchSize = max(1, maximumConcurrentRequests)

        for start in stride(from: 0, to: uniqueWords.count, by: batchSize) {
            let end = min(start + batchSize, uniqueWords.count)
            let batch = Array(uniqueWords[start..<end])
            let batchResults = await withTaskGroup(
                of: (String, WordMetadataResolution).self,
                returning: [(String, WordMetadataResolution)].self
            ) { group in
                for word in batch {
                    group.addTask {
                        let resolution = await self.resolve(
                            text: word,
                            allowNetwork: allowNetwork,
                            refresh: refresh
                        )
                        return (word, resolution)
                    }
                }
                var values: [(String, WordMetadataResolution)] = []
                for await value in group {
                    values.append(value)
                }
                return values
            }
            for (word, resolution) in batchResults {
                results[word] = resolution
            }
        }
        return results
    }
}

public enum SpellingSuggestionSelector {
    public static func bestSuggestion(for text: String, candidates: [String]) -> String? {
        let word = WordTextNormalizer.normalize(text)
        guard word.count >= 3 else { return nil }

        return candidates
            .map(WordTextNormalizer.normalize)
            .filter { !$0.isEmpty && $0 != word }
            .map { candidate in
                (
                    candidate,
                    editDistance(word, candidate),
                    WordMetadataProvider.metadata(for: candidate).hasCompleteRequiredMetadata
                )
            }
            .filter { _, distance, _ in distance <= (word.count >= 7 ? 2 : 1) }
            .sorted {
                if $0.2 != $1.2 { return $0.2 && !$1.2 }
                if $0.1 == $1.1 { return $0.0 < $1.0 }
                return $0.1 < $1.1
            }
            .first?.0
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)

        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous.last ?? max(left.count, right.count)
    }
}

public extension WordMetadata {
    var missingRequiredLabels: [String] {
        var labels: [String] = []
        if WordTextNormalizer.displayText(for: americanPhonetic).isEmpty {
            labels.append("美式音标")
        }
        if WordTextNormalizer.displayText(for: britishPhonetic).isEmpty {
            labels.append("英式音标")
        }
        if WordTextNormalizer.displayText(for: translation).isEmpty {
            labels.append("中文释义")
        }
        return labels
    }

    var hasCompleteRequiredMetadata: Bool {
        missingRequiredLabels.isEmpty
    }

    mutating func fillMissing(from other: WordMetadata) {
        if WordTextNormalizer.displayText(for: americanPhonetic).isEmpty {
            americanPhonetic = other.americanPhonetic
        }
        if WordTextNormalizer.displayText(for: britishPhonetic).isEmpty {
            britishPhonetic = other.britishPhonetic
        }
        if WordTextNormalizer.displayText(for: translation).isEmpty {
            translation = other.translation
        }
        if WordTextNormalizer.displayText(for: sentence).isEmpty {
            sentence = other.sentence
        }
        if WordTextNormalizer.displayText(for: sentenceTranslation).isEmpty,
           sentence == other.sentence {
            sentenceTranslation = other.sentenceTranslation
        }
    }
}
