import XCTest
import SwiftData
@testable import MurmurCore

private func seg(_ text: String, _ start: Double = 0, speaker: Int? = nil) -> TranscriptSegment {
    TranscriptSegment(start: start, end: start + 1, text: text, speakerIndex: speaker)
}

/// Records every request and answers from a closure.
private final class FakeGenerator: TextGenerator, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var prompts: [String] = []
    private(set) var instructions: [String] = []
    let reply: @Sendable (Int) -> String
    init(reply: @escaping @Sendable (Int) -> String) { self.reply = reply }

    func generate(instructions: String, prompt: String) async throws -> String {
        lock.lock()
        prompts.append(prompt)
        self.instructions.append(instructions)
        let n = prompts.count
        lock.unlock()
        return reply(n)
    }
}

final class SummaryParserTests: XCTestCase {
    func testParsesSummaryAndActionItems() {
        let raw = """
        SUMMARY:
        We will ship the Watch app first.
        ACTION ITEMS:
        - Update the timeline | Priya | by Friday
        - Confirm scope | Alex | ?
        - Start the spike | ? | next week
        """
        let result = SummaryParser.parse(raw, template: .meeting)
        XCTAssertEqual(result.text, "We will ship the Watch app first.")
        XCTAssertEqual(result.actionItems.count, 3)
        XCTAssertEqual(result.actionItems[0].owner, "Priya")
        XCTAssertEqual(result.actionItems[0].due, "by Friday")
        XCTAssertNil(result.actionItems[1].due)
        XCTAssertNil(result.actionItems[2].owner)
        XCTAssertEqual(result.actionItems[2].metaLine, "next week")
        XCTAssertEqual(result.actionItems[0].metaLine, "Priya · by Friday")
    }

    func testNoneMeansNoItems() {
        let result = SummaryParser.parse("SUMMARY:\nShort.\nACTION ITEMS:\n- none", template: .meeting)
        XCTAssertEqual(result.text, "Short.")
        XCTAssertTrue(result.actionItems.isEmpty)
    }

    func testReplyWithoutMarkersIsKeptWhole() {
        let result = SummaryParser.parse("Just a paragraph.", template: .meeting)
        XCTAssertEqual(result.text, "Just a paragraph.")
        XCTAssertTrue(result.actionItems.isEmpty)
    }

    func testBulletTemplateIgnoresActionItems() {
        let result = SummaryParser.parse("SUMMARY:\n• One\n• Two\nACTION ITEMS:\n- Do it | Me | Now", template: .bullets)
        XCTAssertEqual(result.text, "• One\n• Two")
        XCTAssertTrue(result.actionItems.isEmpty)
    }

    func testMarkersAreCaseInsensitive() {
        let result = SummaryParser.parse("summary: Hi\naction items:\n- A | B | C", template: .meeting)
        XCTAssertEqual(result.text, "Hi")
        XCTAssertEqual(result.actionItems.first?.text, "A")
    }
}

final class TranscriptChunkerTests: XCTestCase {
    func testKeepsShortTranscriptInOneChunk() {
        XCTAssertEqual(TranscriptChunker.chunks(of: ["a", "b", "c"], maxCharacters: 100), ["a\nb\nc"])
    }

    func testSplitsBetweenLines() {
        let chunks = TranscriptChunker.chunks(of: ["aaaa", "bbbb", "cccc"], maxCharacters: 9)
        XCTAssertEqual(chunks, ["aaaa\nbbbb", "cccc"])
    }

    func testSplitsOverlongLineAtSpaces() {
        let chunks = TranscriptChunker.chunks(of: ["one two three four"], maxCharacters: 9)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 9 })
        XCTAssertEqual(chunks.joined(separator: " ").replacingOccurrences(of: "\n", with: " "), "one two three four")
    }

    func testEmptyInputGivesNoChunks() {
        XCTAssertTrue(TranscriptChunker.chunks(of: [], maxCharacters: 10).isEmpty)
    }

    func testFormatterNamesSpeakersAndSkipsBlankLines() {
        let lines = TranscriptFormatter.lines(
            segments: [seg("Hello.", speaker: 0), seg("  ", 1), seg("Hi.", 2, speaker: 1), seg("Plain.", 3)],
            speakerNames: ["Alex"]
        )
        XCTAssertEqual(lines, ["Alex: Hello.", "Speaker 2: Hi.", "Plain."])
    }
}

final class SummarizerTests: XCTestCase {
    func testShortTranscriptUsesOneRequest() async throws {
        let generator = FakeGenerator { _ in "SUMMARY:\nDone.\nACTION ITEMS:\n- Send it | Sam | Monday" }
        let result = try await Summarizer(generator: generator)
            .summarize(segments: [seg("We agreed Sam sends it Monday.")], speakerNames: [], template: .meeting)
        XCTAssertEqual(generator.prompts.count, 1)
        XCTAssertTrue(generator.prompts[0].contains("We agreed Sam sends it Monday."))
        XCTAssertEqual(result.text, "Done.")
        XCTAssertEqual(result.actionItems.first?.owner, "Sam")
        XCTAssertEqual(result.template, .meeting)
    }

    func testLongTranscriptIsSummarizedInPartsThenCombined() async throws {
        let generator = FakeGenerator { _ in "SUMMARY:\nPart notes.\nACTION ITEMS:\n- none" }
        let segments = (0..<6).map { seg(String(repeating: "word ", count: 20), Double($0)) }
        let progress = ProgressLog()
        let result = try await Summarizer(generator: generator, maxChunkCharacters: 250)
            .summarize(segments: segments, speakerNames: [], template: .lecture) { progress.add($0) }
        // Several part requests plus the final combine request.
        XCTAssertGreaterThan(generator.prompts.count, 2)
        XCTAssertTrue(generator.prompts.last!.contains("Combine"))
        XCTAssertEqual(result.template, .lecture)
        XCTAssertTrue(progress.messages.contains { $0.hasPrefix("Reading part 1") })
        XCTAssertTrue(progress.messages.contains("Putting it together…"))
    }

    func testEmptyTranscriptThrows() async {
        let generator = FakeGenerator { _ in "" }
        do {
            _ = try await Summarizer(generator: generator).summarize(segments: [seg(" ")], speakerNames: [], template: .meeting)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? SummaryError, .emptyTranscript)
        }
        XCTAssertTrue(generator.prompts.isEmpty)
    }

    func testTemplatesUseDifferentInstructions() {
        let all = Set(SummaryTemplate.allCases.map { Summarizer.instructions(for: $0) })
        XCTAssertEqual(all.count, 3)
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ message: String) { lock.lock(); items.append(message); lock.unlock() }
    var messages: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

final class NoteSummaryTests: XCTestCase {
    func testRoundTrip() {
        let original = DemoSummaryService.sample
        XCTAssertEqual(NoteSummary.decode(original.encoded()), original)
    }

    func testPlainTextSummaryStillLoads() {
        let loaded = NoteSummary.decode("An older plain summary.")
        XCTAssertEqual(loaded?.text, "An older plain summary.")
        XCTAssertEqual(loaded?.actionItems.count, 0)
    }

    func testEmptyIsNil() {
        XCTAssertNil(NoteSummary.decode(nil))
        XCTAssertNil(NoteSummary.decode("  \n"))
    }

    func testPlainTextShowsChecklist() {
        let text = DemoSummaryService.sample.plainText
        XCTAssertTrue(text.contains("Action items:"))
        XCTAssertTrue(text.contains("- [x] Update the Q4 timeline and share it (Priya · by Friday)"))
        XCTAssertTrue(text.contains("- [ ] Confirm Watch app scope with design (Alex · this week)"))
    }

    func testExportUsesPlainText() {
        let note = Note(title: "T", createdAt: Date(), duration: 10, source: .recording, status: .ready)
        note.segments = [seg("Hello there.")]
        note.transcript = "Hello there."
        note.summary = DemoSummaryService.sample.encoded()
        let text = Exporter.text(for: note, options: ExportOptions(speakerLabels: false, timestamps: false, summary: true))
        XCTAssertTrue(text.contains("Summary\nThe team chose to ship"))
        XCTAssertFalse(text.contains("\"actionItems\""))
    }
}

@MainActor
final class SummaryControllerTests: XCTestCase {
    func testGenerateReturnsSummaryAndReturnsToIdle() async {
        let controller = SummaryController(service: DemoSummaryService())
        controller.template = .bullets
        let result = await controller.generate(segments: [seg("Hi.")], speakerNames: [])
        XCTAssertEqual(result?.template, .bullets)
        XCTAssertTrue(result?.actionItems.isEmpty ?? false)
        XCTAssertEqual(controller.state, .idle)
    }

    func testUnavailableReportsReason() async {
        let controller = SummaryController(service: DemoSummaryService(availability: .unavailable("No AI here.")))
        let result = await controller.generate(segments: [seg("Hi.")], speakerNames: [])
        XCTAssertNil(result)
        XCTAssertEqual(controller.state, .failed("No AI here."))
        controller.dismissError()
        XCTAssertEqual(controller.state, .idle)
    }

    func testFailureKeepsMessage() async {
        let controller = SummaryController(service: DemoSummaryService(error: .refused))
        let result = await controller.generate(segments: [seg("Hi.")], speakerNames: [])
        XCTAssertNil(result)
        XCTAssertEqual(controller.state, .failed(SummaryError.refused.errorDescription!))
    }

    func testEmptySegmentsFail() async {
        let controller = SummaryController(service: DemoSummaryService())
        let result = await controller.generate(segments: [], speakerNames: [])
        XCTAssertNil(result)
        if case .failed = controller.state {} else { XCTFail("expected failure") }
    }
}

@MainActor
final class SummaryStoreTests: XCTestCase {
    func testSetAndToggleActionItem() throws {
        let container = try MurmurSchema.makeContainer(inMemory: true)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-sum-\(UUID().uuidString)")
        let store = LibraryStore(context: container.mainContext, files: AudioFileStore(directory: dir))
        let note = Note(title: "T", createdAt: Date(), duration: 10, source: .recording, status: .ready)
        container.mainContext.insert(note)

        store.setSummary(DemoSummaryService.sample, for: note)
        let second = NoteSummary.decode(note.summary)!.actionItems[1]
        XCTAssertFalse(second.done)

        store.toggleActionItem(second.id, in: note)
        XCTAssertTrue(NoteSummary.decode(note.summary)!.actionItems[1].done)
        store.toggleActionItem(second.id, in: note)
        XCTAssertFalse(NoteSummary.decode(note.summary)!.actionItems[1].done)

        store.setSummary(nil, for: note)
        XCTAssertNil(note.summary)
    }
}
