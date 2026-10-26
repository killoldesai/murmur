import Foundation
import MurmurCore

/// What the Library and Note screens need from the outside, so CI demos can pass fakes.
struct LibraryDependencies {
    let models: SpeechModelManager
    let queue: TranscriptionQueue
    let importer: ImportQueue
    let files: AudioFileStore
    let makeRecorder: @MainActor () -> RecorderEngine
    let makePlayer: @MainActor () -> PlayerEngine
    let summaries: SummaryService
}
