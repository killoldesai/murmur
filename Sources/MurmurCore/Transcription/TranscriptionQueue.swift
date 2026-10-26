import Foundation
import Observation
import SwiftData

/// Transcribes notes with status `.queued`, one at a time, and saves the result.
///
/// If no engine is available yet (the model is not downloaded) notes simply stay queued.
@MainActor
@Observable
public final class TranscriptionQueue {
    public private(set) var currentNoteID: UUID?
    public private(set) var fraction: Double = 0
    public private(set) var previewSegments: [TranscriptSegment] = []
    public private(set) var etaSeconds: TimeInterval?
    /// Audio seconds transcribed per second of work for the current note (the Mac queue's speed column).
    public private(set) var speedFactor: Double?
    public private(set) var lastFailure: String?

    public var isRunning: Bool { task != nil }

    private let context: ModelContext
    private let engineProvider: @MainActor () -> TranscriptionEngine?
    private let files: AudioFileStore
    private let language: String?
    /// Optional preferences: the language to use and whether to delete audio when done.
    @ObservationIgnored public var settings: AppSettings?
    private let now: @Sendable () -> Date
    private var task: Task<Void, Never>?

    public init(
        context: ModelContext,
        files: AudioFileStore,
        language: String? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        engineProvider: @escaping @MainActor () -> TranscriptionEngine?
    ) {
        self.context = context
        self.files = files
        self.language = language
        self.now = now
        self.engineProvider = engineProvider
    }

    /// Starts working through the queue in the background. Does nothing if already running.
    public func start() {
        guard task == nil else { return }
        task = Task {
            await self.processQueued()
            self.task = nil
        }
    }

    /// Stops the current transcription. The note goes back to `.queued`.
    public func cancel() {
        task?.cancel()
    }

    /// Transcribes every queued note, oldest first. Returns when the queue is empty, no engine
    /// is available, or the task is cancelled.
    public func processQueued() async {
        requeueStale()
        while !Task.isCancelled {
            guard let note = nextQueuedNote() else { return }
            guard let engine = engineProvider() else { return }
            if await transcribe(note, with: engine) == false { return }
        }
    }

    // MARK: - One note

    /// - Returns: `false` when the work was cancelled and the queue should stop.
    private func transcribe(_ note: Note, with engine: TranscriptionEngine) async -> Bool {
        guard let name = note.audioFileName, files.exists(name) else {
            note.status = .failed
            lastFailure = "The audio file for “\(note.title)” is missing."
            save()
            return true
        }

        let noteID = note.id
        note.status = .transcribing
        save()
        currentNoteID = noteID
        fraction = 0
        previewSegments = []
        etaSeconds = nil
        speedFactor = nil
        lastFailure = nil
        let started = now()
        let estimator = ETAEstimator(start: started)
        let clock = now
        let totalSeconds = note.duration

        var cancelled = false
        let options = TranscriptionOptions(language: settings?.language ?? language, vocabulary: dictionaryTerms())
        do {
            let output = try await engine.transcribe(
                audioURL: files.url(for: name),
                duration: note.duration,
                options: options
            ) { update in
                Task { @MainActor [weak self] in
                    guard let self, self.currentNoteID == noteID else { return }
                    self.fraction = max(self.fraction, min(1, update.fraction))
                    self.previewSegments = update.segments
                    self.etaSeconds = estimator.remaining(fraction: self.fraction, at: clock())
                    self.speedFactor = RealtimeFactor.value(
                        audioSeconds: totalSeconds * self.fraction,
                        elapsed: clock().timeIntervalSince(started)
                    )
                }
            }
            try Task.checkCancellation()
            note.segments = output.segments
            note.transcript = output.text
            note.language = output.language
            note.status = .ready
            if settings?.deleteAudioAfterTranscribing == true, !output.segments.isEmpty {
                files.delete(name)
                note.audioFileName = nil
            }
            fraction = 1
            etaSeconds = 0
            previewSegments = output.segments
        } catch is CancellationError {
            cancelled = true
            note.status = .queued
        } catch {
            if Task.isCancelled {
                cancelled = true
                note.status = .queued
            } else {
                note.status = .failed
                lastFailure = error.localizedDescription
            }
        }
        save()
        currentNoteID = nil
        return !cancelled
    }

    // MARK: - Helpers

    /// A note still marked `.transcribing` while nothing is running was cut off by the app
    /// being killed. Put it back in the queue.
    private func requeueStale() {
        guard currentNoteID == nil else { return }
        let all = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        var changed = false
        for note in all where note.status == .transcribing {
            note.status = .queued
            changed = true
        }
        if changed { save() }
    }

    private func nextQueuedNote() -> Note? {
        let all = (try? context.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return all.first { $0.status == .queued }
    }

    private func dictionaryTerms() -> [String] {
        let words = (try? context.fetch(FetchDescriptor<DictionaryWord>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return words.map(\.term).filter { !$0.isEmpty }
    }

    private func save() {
        try? context.save()
    }
}
