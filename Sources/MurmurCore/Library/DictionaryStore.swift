import Foundation
import SwiftData

/// The custom dictionary: words passed to Whisper so it spells names and jargon correctly.
@MainActor
public final class DictionaryStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Newest first.
    public func words() -> [DictionaryWord] {
        (try? context.fetch(FetchDescriptor<DictionaryWord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    public func contains(_ term: String) -> Bool {
        let key = Self.key(term)
        return !key.isEmpty && words().contains { Self.key($0.term) == key }
    }

    /// Adds a word. Returns `nil` when it is blank or already there (ignoring case).
    @discardableResult
    public func add(_ term: String, kind: DictionaryWordKind? = nil) -> DictionaryWord? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !contains(trimmed) else { return nil }
        let word = DictionaryWord(term: trimmed, kind: kind ?? Self.guessKind(trimmed))
        context.insert(word)
        try? context.save()
        return word
    }

    public func remove(_ word: DictionaryWord) {
        context.delete(word)
        try? context.save()
    }

    /// A name when every word is capitalized and otherwise lowercase ("Priya", "Dr. Okafor");
    /// anything else ("CloudKit", "Q4 OKRs", "glycolysis") is a term.
    public static func guessKind(_ term: String) -> DictionaryWordKind {
        let words = term.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty, words.count <= 3 else { return .term }
        for word in words {
            let letters = word.filter(\.isLetter)
            guard let first = letters.first, first.isUppercase else { return .term }
            if letters.dropFirst().contains(where: \.isUppercase) { return .term }
            if word.contains(where: \.isNumber) { return .term }
        }
        return .name
    }

    private static func key(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
