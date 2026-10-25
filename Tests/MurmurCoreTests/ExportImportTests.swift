import XCTest
import AVFoundation
import SwiftData
@testable import MurmurCore

private func seg(_ text: String, _ start: Double, _ end: Double, speaker: Int? = nil) -> TranscriptSegment {
    TranscriptSegment(start: start, end: end, text: text, speakerIndex: speaker)
}

// MARK: - Exporter

final class ExporterTests: XCTestCase {
    private let segments = [
        seg("Okay, let’s start.", 4, 9, speaker: 0),
        seg("Sounds good.", 65.5, 70, speaker: 1),
        seg("No speaker here.", 3700, 3705),
    ]
    private let names = ["Alex", "Priya"]

    func testTextWithEverything() {
        let out = Exporter.text(title: "Sync", segments: segments, speakerNames: names, summary: "We agreed.",
                                options: ExportOptions(speakerLabels: true, timestamps: true, summary: true))
        XCTAssertEqual(out, """
        Sync

        Summary
        We agreed.

        [00:04] Alex: Okay, let’s start.
        [01:05] Priya: Sounds good.
        [1:01:40] No speaker here.

        """)
    }

    func testTextPlain() {
        let out = Exporter.text(title: "Sync", segments: segments, speakerNames: names, summary: "We agreed.",
                                options: ExportOptions(speakerLabels: false, timestamps: false, summary: false))
        XCTAssertEqual(out, "Sync\n\nOkay, let’s start.\nSounds good.\nNo speaker here.\n")
    }

    func testSummaryOptionIgnoredWhenNoSummary() {
        let out = Exporter.text(title: "T", segments: [seg("Hi", 0, 1)], speakerNames: [], summary: nil, options: ExportOptions())
        XCTAssertFalse(out.contains("Summary"))
        let blank = Exporter.text(title: "T", segments: [seg("Hi", 0, 1)], speakerNames: [], summary: "  \n", options: ExportOptions())
        XCTAssertFalse(blank.contains("Summary"))
    }

    func testFallsBackToPlainTranscript() {
        let out = Exporter.text(title: "T", segments: [], fallbackText: "Just text.", speakerNames: [], summary: nil, options: ExportOptions())
        XCTAssertEqual(out, "T\n\nJust text.\n")
    }

    func testUnnamedSpeakerGetsDefaultName() {
        let out = Exporter.text(title: "T", segments: [seg("Hi", 0, 1, speaker: 2)], speakerNames: names, summary: nil, options: ExportOptions())
        XCTAssertTrue(out.contains("Speaker 3: Hi"))
    }

    func testSRT() {
        let out = Exporter.srt(segments: segments, speakerNames: names, options: ExportOptions())
        XCTAssertEqual(out, """
        1
        00:00:04,000 --> 00:00:09,000
        Alex: Okay, let’s start.

        2
        00:01:05,500 --> 00:01:10,000
        Priya: Sounds good.

        3
        01:01:40,000 --> 01:01:45,000
        No speaker here.

        """)
    }

    func testSRTWithoutSpeakersSkipsEmptyAndFixesBadEnd() {
        let out = Exporter.srt(
            segments: [seg("  ", 0, 1), seg("Hello", 2, 2, speaker: 0)],
            speakerNames: names,
            options: ExportOptions(speakerLabels: false)
        )
        XCTAssertEqual(out, "1\n00:00:02,000 --> 00:00:03,000\nHello\n")
        XCTAssertEqual(Exporter.srt(segments: [], speakerNames: [], options: ExportOptions()), "")
    }

    func testSRTTime() {
        XCTAssertEqual(Exporter.srtTime(0), "00:00:00,000")
        XCTAssertEqual(Exporter.srtTime(59.9996), "00:01:00,000")
        XCTAssertEqual(Exporter.srtTime(3661.25), "01:01:01,250")
        XCTAssertEqual(Exporter.srtTime(-3), "00:00:00,000")
        XCTAssertEqual(Exporter.srtTime(.nan), "00:00:00,000")
    }

    func testFileName() {
        XCTAssertEqual(Exporter.fileName(for: "Product sync — Q4/roadmap: draft?"), "Product sync — Q4-roadmap- draft-")
        XCTAssertEqual(Exporter.fileName(for: "   "), "Murmur note")
        XCTAssertEqual(Exporter.fileName(for: String(repeating: "a", count: 200)).count, 80)
    }

    func testFormats() {
        XCTAssertEqual(ExportFormat.allCases.count, 4)
        XCTAssertFalse(ExportFormat.audio.usesTextOptions)
        XCTAssertTrue(ExportFormat.subtitles.usesTextOptions)
        XCTAssertTrue(ExportFormat.copy.usesTextOptions)
    }
}

// MARK: - Export service

@MainActor
final class ExportServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var directory: URL!
    private var files: AudioFileStore!
    private var service: ExportService!

    override func setUp() async throws {
        container = try MurmurSchema.makeContainer(inMemory: true)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-export-\(UUID().uuidString)")
        files = AudioFileStore(directory: directory.appendingPathComponent("audio"))
        try files.ensureDirectory()
        service = ExportService(files: files, tempDirectory: directory.appendingPathComponent("tmp"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        service = nil
        container = nil
    }

    private func makeNote() -> Note {
        let note = Note(title: "Plan: Q4/roadmap")
        note.segments = [seg("Hello there.", 0, 2, speaker: 0)]
        note.speakerNames = ["Alex"]
        container.mainContext.insert(note)
        return note
    }

    func testCopyReturnsText() async throws {
        let artifact = try await service.prepare(note: makeNote(), format: .copy, options: ExportOptions())
        guard case .text(let text) = artifact else { return XCTFail("expected text") }
        XCTAssertTrue(text.contains("Alex: Hello there."))
    }

    func testTextAndSubtitlesWriteNamedFiles() async throws {
        let note = makeNote()
        guard case .file(let txt) = try await service.prepare(note: note, format: .text, options: ExportOptions()),
              case .file(let srt) = try await service.prepare(note: note, format: .subtitles, options: ExportOptions())
        else { return XCTFail("expected files") }
        XCTAssertEqual(txt.lastPathComponent, "Plan- Q4-roadmap.txt")
        XCTAssertEqual(srt.lastPathComponent, "Plan- Q4-roadmap.srt")
        XCTAssertTrue(try String(contentsOf: txt, encoding: .utf8).contains("Hello there."))
        XCTAssertTrue(try String(contentsOf: srt, encoding: .utf8).contains("-->"))
    }

    func testAudioWithoutFileThrows() async {
        do {
            _ = try await service.prepare(note: makeNote(), format: .audio, options: ExportOptions())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ExportError, .noAudio)
        }
    }
}

extension ExportError: Equatable {}

// MARK: - Real audio conversion (macOS AVFoundation)

final class AudioTranscoderTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-audio-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    /// Two seconds of a 440 Hz tone, 44.1 kHz stereo, as a CAF file.
    private func makeToneFile() throws -> URL {
        let url = directory.appendingPathComponent("tone.caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frames: AVAudioFrameCount = 88_200
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(file.processingFormat.channelCount) {
            let data = buffer.floatChannelData![channel]
            for i in 0..<Int(frames) { data[i] = 0.4 * sinf(2 * .pi * 440 * Float(i) / 44_100) }
        }
        try file.write(from: buffer)
        return url
    }

    func testConvertsToWhisperFormat() async throws {
        let source = try makeToneFile()
        let destination = directory.appendingPathComponent("out.wav")
        let duration = try await AudioTranscoder.convertToWhisperWAV(from: source, to: destination) { _ in }
        XCTAssertEqual(duration, 2, accuracy: 0.1)
        let out = try AVAudioFile(forReading: destination)
        XCTAssertEqual(out.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(out.fileFormat.channelCount, 1)
        XCTAssertEqual(Double(out.length) / 16_000, 2, accuracy: 0.15)
    }

    func testM4ARoundTrip() async throws {
        let source = try makeToneFile()
        let m4a = directory.appendingPathComponent("share.m4a")
        try await AudioTranscoder.exportM4A(from: source, to: m4a)
        XCTAssertTrue(FileManager.default.fileExists(atPath: m4a.path))
        let wav = directory.appendingPathComponent("back.wav")
        let duration = try await AudioTranscoder.convertToWhisperWAV(from: m4a, to: wav) { _ in }
        XCTAssertEqual(duration, 2, accuracy: 0.2)
    }

    func testFileWithoutAudioFails() async {
        let bogus = directory.appendingPathComponent("not-audio.mp3")
        try? Data("hello".utf8).write(to: bogus)
        do {
            _ = try await AudioTranscoder.convertToWhisperWAV(from: bogus, to: directory.appendingPathComponent("x.wav")) { _ in }
            XCTFail("expected failure")
        } catch {
            // Any error is fine: the file is not audio.
        }
    }
}

// MARK: - Import queue

private struct FakeConverter: AudioConverting {
    var failFor: Set<String> = []
    var duration: TimeInterval = 12

    func convert(from source: URL, to destination: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> TimeInterval {
        onProgress(0.5)
        if failFor.contains(source.lastPathComponent) { throw AudioTranscodeError.cannotRead }
        FileManager.default.createFile(atPath: destination.path, contents: Data([1, 2, 3]))
        return duration
    }
}

@MainActor
final class ImportQueueTests: XCTestCase {
    private var container: ModelContainer!
    private var directory: URL!
    private var files: AudioFileStore!

    override func setUp() async throws {
        container = try MurmurSchema.makeContainer(inMemory: true)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-import-\(UUID().uuidString)")
        files = AudioFileStore(directory: directory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        container = nil
    }

    private func makeQueue(_ converter: AudioConverting = FakeConverter()) -> ImportQueue {
        ImportQueue(context: container.mainContext, files: files, converter: converter)
    }

    private func notes() -> [Note] {
        (try? container.mainContext.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    func testFormats() {
        XCTAssertTrue(ImportFormats.isSupported(URL(fileURLWithPath: "/a/Podcast.MP3")))
        XCTAssertTrue(ImportFormats.isSupported(URL(fileURLWithPath: "/a/clip.mov")))
        XCTAssertFalse(ImportFormats.isSupported(URL(fileURLWithPath: "/a/doc.pdf")))
        XCTAssertEqual(ImportFormats.title(for: URL(fileURLWithPath: "/a/Customer interview — Maria.mp4")), "Customer interview — Maria")
    }

    func testImportsFilesInOrderAsQueuedNotes() async {
        let queue = makeQueue()
        var added = 0
        queue.onNoteAdded = { added += 1 }
        let skipped = queue.enqueue([
            URL(fileURLWithPath: "/tmp/a.m4a"), URL(fileURLWithPath: "/tmp/notes.pdf"), URL(fileURLWithPath: "/tmp/b.mp3"),
        ])
        XCTAssertEqual(skipped, 1)
        XCTAssertEqual(queue.items.count, 2)
        let ok = await waitUntilDone(queue)
        XCTAssertTrue(ok)
        XCTAssertEqual(queue.summary, "2 of 2 done")
        XCTAssertEqual(added, 2)
        let all = notes()
        XCTAssertEqual(all.map(\.title), ["a", "b"])
        XCTAssertTrue(all.allSatisfy { $0.status == .queued && $0.source == .importedFile && $0.duration == 12 })
        XCTAssertTrue(all.allSatisfy { files.exists($0.audioFileName!) && $0.audioFileName!.hasSuffix(".wav") })
    }

    func testFailureDoesNotStopTheQueue() async {
        let queue = makeQueue(FakeConverter(failFor: ["bad.mp3"]))
        queue.enqueue([URL(fileURLWithPath: "/tmp/bad.mp3"), URL(fileURLWithPath: "/tmp/good.mp3")])
        _ = await waitUntilDone(queue)
        if case .failed(let message) = queue.items[0].state {
            XCTAssertEqual(message, "This file couldn’t be read.")
        } else { XCTFail("first item should have failed") }
        XCTAssertEqual(queue.items[1].state, .done)
        XCTAssertEqual(notes().count, 1)
        XCTAssertEqual(queue.summary, "1 of 2 done")
    }

    func testDeleteSourceAfterImport() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("inbox.m4a")
        FileManager.default.createFile(atPath: source.path, contents: Data([9]))
        let queue = makeQueue()
        queue.enqueue([source], deleteSourcesAfter: true)
        _ = await waitUntilDone(queue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testClearFinished() async {
        let queue = makeQueue(FakeConverter(failFor: ["bad.mp3"]))
        queue.enqueue([URL(fileURLWithPath: "/tmp/bad.mp3"), URL(fileURLWithPath: "/tmp/good.mp3")])
        _ = await waitUntilDone(queue)
        queue.clearFinished()
        XCTAssertEqual(queue.items.count, 1)
        XCTAssertEqual(makeQueue().summary, "Nothing queued")
    }

    private func waitUntilDone(_ queue: ImportQueue) async -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if !queue.isWorking && !queue.items.isEmpty { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }
}
