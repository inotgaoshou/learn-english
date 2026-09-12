import Foundation

public enum DictationMode: String, CaseIterable, Codable, Equatable {
    case ordered
    case shuffled

    public var title: String {
        switch self {
        case .ordered:
            return "按顺序"
        case .shuffled:
            return "打乱"
        }
    }
}
