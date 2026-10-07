import Foundation

enum OnlineWordMetadataError: LocalizedError {
    case invalidWord
    case notFound
    case badResponse

    var errorDescription: String? {
        switch self {
        case .invalidWord:
            return "请输入英文单词后再联网补全。"
        case .notFound:
            return "在线词典暂未查到这个词。"
        case .badResponse:
            return "在线词典返回异常，请稍后再试。"
        }
    }
}

struct OnlineWordMetadataService {
    func metadata(for text: String) async throws -> WordMetadata {
        let cleanText = WordTextNormalizer.normalize(text)
        guard !cleanText.isEmpty,
              cleanText.range(of: #"^[a-z][a-z '\-]*$"#, options: .regularExpression) != nil,
              let encodedWord = cleanText.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encodedWord)") else {
            throw OnlineWordMetadataError.invalidWord
        }

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnlineWordMetadataError.badResponse
        }
        guard httpResponse.statusCode != 404 else {
            throw OnlineWordMetadataError.notFound
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw OnlineWordMetadataError.badResponse
        }

        return try FreeDictionaryMetadataParser.metadata(from: data)
    }
}
