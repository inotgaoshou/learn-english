import Foundation
import UIKit
import Vision

final class OCRService {
    enum OCRServiceError: LocalizedError {
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "图片无法读取。"
            }
        }
    }

    func recognizeWords(from images: [UIImage]) async throws -> [WordItem] {
        let text = try await recognizeText(from: images)
        return WordTextExtractor.extractWords(from: text)
    }

    func recognizeText(from images: [UIImage]) async throws -> String {
        var recognizedPages: [String] = []

        for image in images {
            guard let cgImage = image.cgImage else {
                continue
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "zh-Hans"]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
            try handler.perform([request])

            let pageText = request.results?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n") ?? ""

            recognizedPages.append(pageText)
        }

        return recognizedPages.joined(separator: "\n\n")
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .down:
            self = .down
        case .left:
            self = .left
        case .right:
            self = .right
        case .upMirrored:
            self = .upMirrored
        case .downMirrored:
            self = .downMirrored
        case .leftMirrored:
            self = .leftMirrored
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
