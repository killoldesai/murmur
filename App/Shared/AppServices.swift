import Foundation
import SwiftData
import AVFoundation
import MurmurCore
import MurmurWhisper

/// Creates the long-lived objects the screens share: the model manager and the transcription
/// queue. One instance lives for the whole app run.
@MainActor
final class AppServices {
    let models: SpeechModelManager
    let queue: TranscriptionQueue
    let importer: ImportQueue
    let entitlements: EntitlementController
    let settings = AppSettings()
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
        let queue = TranscriptionQueue(
            context: container.mainContext,
            files: .standard,
            engineProvider: { engines.current() }
        )
        queue.settings = settings
        self.queue = queue
        let importer = ImportQueue(context: container.mainContext, files: .standard)
        // Imported files become queued notes; start transcribing as soon as one arrives.
        importer.onNoteAdded = { queue.start() }
        self.importer = importer
        self.entitlements = EntitlementController(store: StoreKitPurchaseStore())
    }
}

extension AppServices {
    /// Shows the system microphone prompt (once; later calls return the saved answer).
    func requestMicrophone() async {
        _ = await AVAudioApplication.requestRecordPermission()
    }

    var libraryDependencies: LibraryDependencies {
        LibraryDependencies(
            models: models,
            queue: queue,
            importer: importer,
            files: .standard,
            makeRecorder: { AVAudioRecorderEngine() },
            makePlayer: { AVAudioPlayerEngine() },
            summaries: OnDeviceSummaryService(),
            entitlements: entitlements,
            settings: settings
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
