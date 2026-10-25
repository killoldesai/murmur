import Foundation
import SwiftData
import MurmurCore
import MurmurWhisper

/// Creates the long-lived objects the screens share: the model manager and the transcription
/// queue. One instance lives for the whole app run.
@MainActor
final class AppServices {
    let models: SpeechModelManager
    let queue: TranscriptionQueue
    let container: ModelContainer
    private let network: NetworkMonitor
    private let engines: EngineCache

    init(container: ModelContainer) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Murmur/Models", isDirectory: true)
        let network = NetworkMonitor()
        self.network = network
        let models = SpeechModelManager(
            downloader: WhisperKitDownloader(downloadBase: base),
            baseDirectory: base,
            isOnExpensiveNetwork: { network.isMetered }
        )
        let engines = EngineCache(models: models)
        self.container = container
        self.models = models
        self.engines = engines
        self.queue = TranscriptionQueue(
            context: container.mainContext,
            files: .standard,
            engineProvider: { engines.current() }
        )
    }
}

extension AppServices {
    var libraryDependencies: LibraryDependencies {
        LibraryDependencies(
            models: models,
            queue: queue,
            files: .standard,
            makeRecorder: { AVAudioRecorderEngine() },
            makePlayer: { AVAudioPlayerEngine() }
        )
    }
}

/// Keeps one `WhisperKitEngine` per model folder so the model is loaded once, not per note.
@MainActor
final class EngineCache {
    private let models: SpeechModelManager
    private var engine: WhisperKitEngine?
    private var folder: URL?

    init(models: SpeechModelManager) { self.models = models }

    func current() -> TranscriptionEngine? {
        guard let url = models.readyFolder else { return nil }
        if folder != url {
            engine = WhisperKitEngine(modelFolder: url)
            folder = url
        }
        return engine
    }
}
