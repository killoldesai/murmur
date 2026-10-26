import XCTest
import SwiftData
@testable import MurmurCore

private func seg(_ text: String, _ start: Double = 0, speaker: Int? = nil) -> TranscriptSegment {
    TranscriptSegment(start: start, end: start + 1, text: text, speakerIndex: speaker)
}

final class TextSearchTests: XCTestCase {
    func testFindsIgnoringCaseAndAccents() {
        let found = TextSearch.ranges(of: "cafe", in: "Café, CAFE and cafe.")
        XCTAssertEqual(found.count, 3)
    }

    func testEmptyQueryFindsNothing() {
        XCTAssertTrue(TextSearch.ranges(of: "", in: "abc").isEmpty)
        XCTAssertTrue(TextSearch.offsets(of: "x", in: "abc").isEmpty)
    }

    func testOffsets() {
        XCTAssertEqual(TextSearch.offsets(of: "ab", in: "ab cab ab"), [0..<2, 4..<6, 7..<9])
    }

    func testReplacingAllDoesNotRematchReplacement() {
        let result = TextSearch.replacingAll(of: "a", with: "aa", in: "banana")
        XCTAssertEqual(result.text, "baanaanaa")
        XCTAssertEqual(result.count, 3)
    }

    func testReplacingOneOccurrence() {
        XCTAssertEqual(TextSearch.replacing(occurrence: 1, of: "Jordon", with: "Jordan", in: "Jordon and Jordon"), "Jordon and Jordan")
        XCTAssertNil(TextSearch.replacing(occurrence: 2, of: "Jordon", with: "Jordan", in: "Jordon and Jordon"))
    }

    func testSnippetKeepsShortTextWhole() {
        let text = "Over to you, Jordon, how long?"
        let range = TextSearch.ranges(of: "jordon", in: text)[0]
        let snippet = TextSearch.snippet(in: text, range: range)
        XCTAssertEqual(snippet, TextSearch.Snippet(pre: "Over to you, ", word: "Jordon", post: ", how long?"))
    }

    func testSnippetCutsLongTextAtWordBoundaries() {
        let text = String(repeating: "alpha beta gamma ", count: 10) + "NEEDLE " + String(repeating: "delta epsilon zeta ", count: 10)
        let range = TextSearch.ranges(of: "needle", in: text)[0]
        let snippet = TextSearch.snippet(in: text, range: range, before: 20, after: 30)
        XCTAssertTrue(snippet.pre.hasPrefix("…"))
        XCTAssertTrue(snippet.post.hasSuffix("…"))
        XCTAssertEqual(snippet.word, "NEEDLE")
        // No half words: every piece is made of whole words from the text.
        let words = Set(text.split(separator: " ").map(String.init))
        for piece in snippet.pre.dropFirst().split(separator: " ") { XCTAssertTrue(words.contains(String(piece)), String(piece)) }
        for piece in snippet.post.dropLast().split(separator: " ") { XCTAssertTrue(words.contains(String(piece)), String(piece)) }
    }
}

@MainActor
final class NoteSearchTests: XCTestCase {
    private func note(_ title: String, _ lines: [String], summary: NoteSummary? = nil) -> Note {
        let n = Note(title: title, createdAt: Date(), duration: 60, source: .recording, status: .ready)
        n.segments = lines.enumerated().map { seg($0.element, Double($0.offset) * 10) }
        n.transcript = lines.joined(separator: "\n")
        n.summary = summary?.encoded()
        return n
    }

    func testFindsHitsWithTimestampsAndCounts() {
        let a = note("A", ["The Watch is first.", "Nothing here.", "Watch again, and watch once more.", "Third watch."])
        let results = NoteSearch.search("watch", in: [a])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].count, 4)
        XCTAssertEqual(results[0].hits.count, 3)
        XCTAssertEqual(results[0].hits[0].label, "00:00")
        XCTAssertEqual(results[0].hits[2].label, "00:20")
        XCTAssertEqual(results[0].countText, "4 matches")
    }

    func testScopes() {
        let summary = NoteSummary(template: .meeting, text: "Ship the Apple Watch app first.")
        let n = note("N", ["A watch on my wrist."], summary: summary)
        XCTAssertEqual(NoteSearch.search("watch", in: [n], scope: .transcripts).first?.count, 1)
        XCTAssertEqual(NoteSearch.search("watch", in: [n], scope: .summaries).first?.count, 1)
        XCTAssertEqual(NoteSearch.search("watch", in: [n], scope: .all).first?.count, 2)
        XCTAssertTrue(NoteSearch.search("watch", in: [n], scope: .summaries).first?.hits.first?.isSummary ?? false)
        XCTAssertEqual(NoteSearch.search("watch", in: [n], scope: .summaries).first?.hits.first?.label, "AI")
    }

    func testSummaryHitIsNotCrowdedOut() {
        let summary = NoteSummary(template: .meeting, text: "A watch summary.")
        let n = note("N", ["watch 1", "watch 2", "watch 3", "watch 4"], summary: summary)
        let hits = NoteSearch.search("watch", in: [n], maxHitsPerNote: 3)[0].hits
        XCTAssertEqual(hits.count, 3)
        XCTAssertTrue(hits.last!.isSummary)
    }

    func testNotesWithoutMatchesAreSkippedAndOrderKept() {
        let a = note("A", ["alpha"]), b = note("B", ["beta"]), c = note("C", ["alpha again"])
        let results = NoteSearch.search("alpha", in: [a, b, c])
        XCTAssertEqual(results.map { $0.note.title }, ["A", "C"])
        XCTAssertEqual(NoteSearch.summaryLine(for: results), "2 results in 2 notes")
        XCTAssertEqual(NoteSearch.summaryLine(for: Array(results.prefix(1))), "1 result in 1 note")
    }

    func testBlankQueryGivesNothing() {
        XCTAssertTrue(NoteSearch.search("   ", in: [note("A", ["alpha"])]).isEmpty)
    }

    func testNoteWithOnlyPlainTranscriptIsSearched() {
        let n = Note(title: "P", createdAt: Date(), duration: 5, source: .recording, status: .ready)
        n.transcript = "plain words here"
        let results = NoteSearch.search("words", in: [n])
        XCTAssertEqual(results.first?.hits.first?.label, "")
    }
}

@MainActor
final class DictionaryStoreTests: XCTestCase {
    /// The container must outlive the store, or the in-memory data is freed under it.
    private var keep: ModelContainer?

    private func make() throws -> (DictionaryStore, ModelContainer) {
        let container = try MurmurSchema.makeContainer(inMemory: true)
        keep = container
        return (DictionaryStore(context: container.mainContext), container)
    }

    func testAddTrimsAndRejectsBlankAndDuplicates() throws {
        let (store, _) = try make()
        XCTAssertNotNil(store.add("  Priya "))
        XCTAssertNil(store.add("priya"))
        XCTAssertNil(store.add("   "))
        XCTAssertEqual(store.words().map(\.term), ["Priya"])
        XCTAssertTrue(store.contains("PRIYA"))
    }

    func testKindGuess() {
        XCTAssertEqual(DictionaryStore.guessKind("Priya"), .name)
        XCTAssertEqual(DictionaryStore.guessKind("Dr. Okafor"), .name)
        XCTAssertEqual(DictionaryStore.guessKind("CloudKit"), .term)
        XCTAssertEqual(DictionaryStore.guessKind("Q4 OKRs"), .term)
        XCTAssertEqual(DictionaryStore.guessKind("glycolysis"), .term)
        XCTAssertEqual(DictionaryStore.guessKind("one two three four"), .term)
    }

    func testRemoveAndNewestFirst() throws {
        let (store, _) = try make()
        let first = store.add("Alpha")!
        first.createdAt = Date(timeIntervalSince1970: 100)
        let second = store.add("Beta")!
        second.createdAt = Date(timeIntervalSince1970: 200)
        XCTAssertEqual(store.words().map(\.term), ["Beta", "Alpha"])
        store.remove(second)
        XCTAssertEqual(store.words().map(\.term), ["Alpha"])
    }
}

@MainActor
final class FindReplaceTests: XCTestCase {
    private func make(find: String = "Jordon", replacement: String = "Jordan") throws -> (FindReplaceController, Note, DictionaryStore) {
        let container = try MurmurSchema.makeContainer(inMemory: true)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-fr-\(UUID().uuidString)")
        let library = LibraryStore(context: container.mainContext, files: AudioFileStore(directory: dir))
        let dictionary = DictionaryStore(context: container.mainContext)
        let note = Note(title: "T", createdAt: Date(), duration: 60, source: .recording, status: .ready)
        note.segments = [
            seg("Okay, let's start.", 0),
            seg("Over to you, Jordon, how long?", 10),
            seg("Jordon estimated three weeks. Ask jordon.", 20),
            seg("So Jordon starts next week.", 30)
        ]
        note.transcript = note.segments.joinedText
        container.mainContext.insert(note)
        keep = container
        let controller = FindReplaceController(note: note, library: library, dictionary: dictionary, find: find, replacement: replacement)
        return (controller, note, dictionary)
    }
    private var keep: ModelContainer?

    func testCountsAndStepping() throws {
        let (c, _, _) = try make()
        XCTAssertEqual(c.matches.count, 4)
        XCTAssertEqual(c.counterText, "1 of 4")
        c.next(); c.next()
        XCTAssertEqual(c.counterText, "3 of 4")
        c.next(); c.next()
        XCTAssertEqual(c.counterText, "1 of 4")
        c.previous()
        XCTAssertEqual(c.counterText, "4 of 4")
    }

    func testEmptyAndNoMatches() throws {
        let (c, _, _) = try make(find: "")
        XCTAssertEqual(c.counterText, "")
        XCTAssertFalse(c.canReplace)
        c.setFind("zzz")
        XCTAssertEqual(c.counterText, "No matches")
        XCTAssertFalse(c.replaceCurrent())
        XCTAssertEqual(c.replaceAll(), 0)
    }

    func testReplaceCurrentMovesOnAndSaves() throws {
        let (c, note, _) = try make()
        XCTAssertTrue(c.replaceCurrent())
        XCTAssertEqual(c.matches.count, 3)
        XCTAssertEqual(c.counterText, "1 of 3")
        XCTAssertEqual(c.current?.segmentIndex, 2)
        XCTAssertEqual(note.segments[1].text, "Over to you, Jordan, how long?")
        XCTAssertTrue(note.transcript.contains("Over to you, Jordan"))
    }

    func testReplaceLastWrapsToFirst() throws {
        let (c, _, _) = try make()
        c.next(); c.next(); c.next()
        XCTAssertTrue(c.replaceCurrent())
        XCTAssertEqual(c.matches.count, 3)
        XCTAssertEqual(c.currentIndex, 0)
    }

    func testReplacementContainingFindIsNotMatchedAgain() throws {
        let (c, note, _) = try make(find: "Jordon", replacement: "Jordon Jr")
        XCTAssertTrue(c.replaceCurrent())
        // Next current is the following original match, not the text just inserted.
        XCTAssertEqual(c.current?.segmentIndex, 2)
        XCTAssertEqual(note.segments[1].text, "Over to you, Jordon Jr, how long?")
        XCTAssertEqual(c.matches.count, 4)
        XCTAssertEqual(c.currentIndex, 1)
    }

    func testReplaceAll() throws {
        let (c, note, _) = try make()
        XCTAssertEqual(c.replaceAll(), 4)
        XCTAssertTrue(c.matches.isEmpty)
        XCTAssertEqual(c.counterText, "No matches")
        XCTAssertEqual(note.segments[2].text, "Jordan estimated three weeks. Ask Jordan.")
        XCTAssertFalse(note.transcript.lowercased().contains("jordon"))
    }

    func testDictionaryAddHonoursToggle() throws {
        let (c, _, dictionary) = try make()
        c.addToDictionary = false
        c.replaceCurrent()
        XCTAssertTrue(dictionary.words().isEmpty)
        c.addToDictionary = true
        c.replaceAll()
        XCTAssertEqual(dictionary.words().map(\.term), ["Jordan"])
    }

    func testSpansMarkCurrent() throws {
        let (c, _, _) = try make()
        c.next()
        let spans = c.spans(inSegment: 2)
        XCTAssertEqual(spans.count, 2)
        XCTAssertTrue(spans[0].isCurrent)
        XCTAssertFalse(spans[1].isCurrent)
        XCTAssertEqual(spans[0].offset, 0)
        XCTAssertEqual(spans[0].length, 6)
        XCTAssertTrue(c.spans(inSegment: 0).isEmpty)
    }
}

@MainActor
final class SearchContextTests: XCTestCase {
    private var keep: ModelContainer?

    private func makeNote(_ texts: [String]) throws -> Note {
        let container = try MurmurSchema.makeContainer(inMemory: true)
        keep = container
        let note = Note(title: "Test", createdAt: Date(), duration: 60, source: .recording, status: .ready)
        note.segments = texts.enumerated().map { seg($1, Double($0) * 10) }
        container.mainContext.insert(note)
        return note
    }

    func testMatchesGetNeighbourLines() throws {
        let note = try makeNote(["zero", "one", "two Watch", "three", "four", "five", "six", "seven Watch", "eight"])
        let lines = SearchContext.lines(for: note, query: "watch", radius: 1)
        XCTAssertEqual(lines.map(\.text), ["one", "two Watch", "three", "six", "seven Watch", "eight"])
        XCTAssertEqual(lines.map(\.isMatch), [false, true, false, false, true, false])
        XCTAssertEqual(lines[1].spans.first?.offset, 4)
        XCTAssertEqual(lines[1].spans.first?.length, 5)
    }

    func testEmptyQueryOrNoMatchGivesNothing() throws {
        let note = try makeNote(["alpha", "beta"])
        XCTAssertTrue(SearchContext.lines(for: note, query: "  ").isEmpty)
        XCTAssertTrue(SearchContext.lines(for: note, query: "zebra").isEmpty)
    }

    func testLimitsMatches() throws {
        let note = try makeNote(Array(repeating: "hit", count: 20))
        let lines = SearchContext.lines(for: note, query: "hit", radius: 0, maxMatches: 3)
        XCTAssertEqual(lines.count, 3)
    }
}
