import XCTest
import SwiftData
@testable import MurmurCore

@MainActor
final class ModelTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        try MurmurSchema.makeContainer(inMemory: true).mainContext
    }

    func testDefaults() {
        let note = Note()
        XCTAssertEqual(note.title, "Untitled")
        XCTAssertEqual(note.duration, 0)
        XCTAssertEqual(note.status, .ready)
        XCTAssertEqual(note.source, .recording)
        XCTAssertTrue(note.segments.isEmpty)
        XCTAssertNil(note.folder)
        XCTAssertEqual(Folder().colorIndex, 0)
        XCTAssertEqual(DictionaryWord(term: "Murmur").kind, .term)
    }

    func testNoteRoundTripsThroughStore() throws {
        let context = try makeContext()
        let note = Note(title: "Product sync", duration: 2530, audioFileName: "a1.m4a",
                        source: .watch, status: .transcribing)
        note.segments = [
            TranscriptSegment(start: 0, end: 4.5, text: "Hello everyone.", speakerIndex: 0),
            TranscriptSegment(start: 4.5, end: 9, text: "Let's begin.", speakerIndex: 1),
        ]
        note.bookmarks = [12.5, 300]
        note.speakerNames = ["Ana", "Ben"]
        note.summary = "Kickoff."
        note.language = "en"
        context.insert(note)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Note>())
        XCTAssertEqual(fetched.count, 1)
        let n = try XCTUnwrap(fetched.first)
        XCTAssertEqual(n.title, "Product sync")
        XCTAssertEqual(n.duration, 2530)
        XCTAssertEqual(n.audioFileName, "a1.m4a")
        XCTAssertEqual(n.source, .watch)
        XCTAssertEqual(n.status, .transcribing)
        XCTAssertEqual(n.segments, note.segments)
        XCTAssertEqual(n.bookmarks, [12.5, 300])
        XCTAssertEqual(n.speakerNames, ["Ana", "Ben"])
        XCTAssertEqual(n.summary, "Kickoff.")
        XCTAssertEqual(n.language, "en")
    }

    func testUnknownRawValuesFallBackSafely() {
        let note = Note()
        note.sourceRaw = "from-the-future"
        note.statusRaw = "from-the-future"
        XCTAssertEqual(note.source, .recording)
        XCTAssertEqual(note.status, .ready)
    }

    func testFolderRelationshipAndDeleteKeepsNotes() throws {
        let context = try makeContext()
        let folder = Folder(name: "Work", colorIndex: 2)
        let note = Note(title: "Standup")
        context.insert(folder)
        context.insert(note)
        note.folder = folder
        try context.save()

        XCTAssertEqual(folder.notes?.count, 1)
        XCTAssertEqual(folder.notes?.first?.title, "Standup")

        context.delete(folder)
        try context.save()

        let notes = try context.fetch(FetchDescriptor<Note>())
        XCTAssertEqual(notes.count, 1, "Deleting a folder must not delete its notes")
        XCTAssertNil(notes.first?.folder)
    }

    func testDictionaryWordKinds() throws {
        let context = try makeContext()
        context.insert(DictionaryWord(term: "WhisperKit", kind: .term))
        context.insert(DictionaryWord(term: "Priya", kind: .name))
        try context.save()
        let words = try context.fetch(FetchDescriptor<DictionaryWord>(sortBy: [SortDescriptor(\.term)]))
        XCTAssertEqual(words.map(\.term), ["Priya", "WhisperKit"])
        XCTAssertEqual(words.map(\.kind), [.name, .term])
    }

    func testIndexPlayingAt() {
        let segs = [
            TranscriptSegment(start: 2, end: 5, text: "a"),
            TranscriptSegment(start: 5, end: 8, text: "b"),
            TranscriptSegment(start: 10, end: 12, text: "c"),
        ]
        XCTAssertNil(segs.indexPlaying(at: 0))
        XCTAssertNil(segs.indexPlaying(at: 1.99))
        XCTAssertEqual(segs.indexPlaying(at: 2), 0)
        XCTAssertEqual(segs.indexPlaying(at: 4.9), 0)
        XCTAssertEqual(segs.indexPlaying(at: 5), 1)
        XCTAssertEqual(segs.indexPlaying(at: 9), 1, "A gap resolves to the previous segment")
        XCTAssertEqual(segs.indexPlaying(at: 10), 2)
        XCTAssertEqual(segs.indexPlaying(at: 999), 2)
        XCTAssertNil([TranscriptSegment]().indexPlaying(at: 3))
    }

    func testJoinedText() {
        let segs = [TranscriptSegment(start: 0, end: 1, text: "One."),
                    TranscriptSegment(start: 1, end: 2, text: "Two.")]
        XCTAssertEqual(segs.joinedText, "One.\nTwo.")
    }
}
