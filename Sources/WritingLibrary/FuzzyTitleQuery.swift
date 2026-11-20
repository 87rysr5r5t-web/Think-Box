import Foundation

public struct FuzzyTitleQuery {
    private let words: [Substring]

    public init(_ query: String) {
        words = Self.normalize(query).split(whereSeparator: \.isWhitespace)
    }

    public func matches(_ title: String) -> Bool {
        let normalized = Self.normalize(title)
        return words.allSatisfy { word in
            var remainder = normalized[...]
            for character in word {
                guard let match = remainder.firstIndex(of: character) else { return false }
                remainder = remainder[remainder.index(after: match)...]
            }
            return true
        }
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
