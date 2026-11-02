import Foundation

public struct ClipboardEntry: Identifiable, Equatable {
    public let id: String
    public let text: String
    public let copiedAt: Date
    public let source: String
    public let sourceBundleID: String
    public let pinned: Bool

    public init(id: String = UUID().uuidString, text: String, copiedAt: Date = Date(), source: String = "Unknown", sourceBundleID: String = "", pinned: Bool = false) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
        self.source = source
        self.sourceBundleID = sourceBundleID
        self.pinned = pinned
    }
}

public enum CompletionMatcher {
    public static func matches(_ entries: [ClipboardEntry], query: String) -> [ClipboardEntry] {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return entries.compactMap { entry -> (ClipboardEntry, Int)? in
            if query.isEmpty { return (entry, 0) }
            guard let range = entry.text.range(of: query, options: options) else { return nil }
            return (entry, range.lowerBound == entry.text.startIndex ? 0 : 1)
        }.sorted { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            if a.0.copiedAt != b.0.copiedAt { return a.0.copiedAt > b.0.copiedAt }
            return a.0.id < b.0.id
        }.map { $0.0 }
    }
}

public struct CompletionSession {
    private let prefix: String
    private let suffix: String
    private let anchor: Int
    public private(set) var query = ""
    public var replacementRange: NSRange { NSRange(location: anchor, length: query.utf16.count) }

    public init?(text: String, selection: NSRange) {
        guard selection.length == 0, let range = Range(selection, in: text),
              range.lowerBound == text.endIndex || text.indices.contains(range.lowerBound) else { return nil }
        prefix = String(text[..<range.lowerBound])
        suffix = String(text[range.upperBound...])
        anchor = selection.location
    }

    public mutating func observe(text: String, selection: NSRange) -> Bool {
        guard let observed = queryIn(text: text, selection: selection) else { return false }
        query = observed
        return true
    }

    public func validates(text: String, selection: NSRange) -> Bool {
        guard let observed = queryIn(text: text, selection: selection) else { return false }
        return observed.utf16.elementsEqual(query.utf16)
    }

    private func queryIn(text: String, selection: NSRange) -> String? {
        guard selection.length == 0,
              text.utf16.starts(with: prefix.utf16),
              text.utf16.suffix(suffix.utf16.count).elementsEqual(suffix.utf16),
              text.utf16.count >= prefix.utf16.count + suffix.utf16.count else { return nil }
        let length = text.utf16.count - prefix.utf16.count - suffix.utf16.count
        guard selection.location == anchor + length,
              let range = Range(NSRange(location: anchor, length: length), in: text) else { return nil }
        return String(text[range])
    }
}
