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
    #if os(iOS)
    /// Recordings from the Apple Watch arrive here and become queued notes.
    let watchLink = WatchConnectivityLink()
    let watchInbox: WatchInbox
    #endif
    private let network: NetworkMonitor
    private let engines: EngineCache

    init(container: ModelContainer, syncState: SyncState = .off) {
        settings.syncState = syncState
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
        // Recordings are re-encoded to M4A after transcribing when the Audio format setting is M4A.
        queue.audioCompactor = { source, destination in
            try await AudioTranscoder.exportM4A(from: source, to: destination)
        }
        self.queue = queue
        let importer = ImportQueue(context: container.mainContext, files: .standard)
        let appSettings = settings
        importer.defaultFolder = { appSettings.defaultFolderID }
        // Imported files become queued notes; start transcribing as soon as one arrives.
        importer.onNoteAdded = { queue.start() }
        self.importer = importer
        self.entitlements = EntitlementController(store: StoreKitPurchaseStore())
        #if os(iOS)
        let inbox = WatchInbox(context: container.mainContext, files: .standard, converter: WhisperWAVConverter())
        self.watchInbox = inbox
        watchLink.onFileReceived = { url, transfer in
            Task { @MainActor in
                if await inbox.receive(fileURL: url, transfer: transfer) != nil {
                    appSettings.noteWatchRecordingReceived()
                    queue.start()
                }
                try? FileManager.default.removeItem(at: url)
            }
        }
        #endif
    }
}

#if os(iOS)
extension AppServices {
    /// Starts Watch Connectivity and tells the watch whether Pro is unlocked.
    func startWatch() {
        watchLink.activate()
        watchLink.publish(isPro: entitlements.isPro)
    }

    func publishPro() {
        watchLink.publish(isPro: entitlements.isPro)
    }
}
#endif

extension AppServices {
    /// Shows the system microphone prompt (once; later calls return the saved answer).
    func requestMicrophone() async {
        _ = await AVAudioApplication.requestRecordPermission()
    }

    var libraryDependencies: LibraryDependencies {
        let settings = self.settings
        return LibraryDependencies(
            models: models,
            queue: queue,
            importer: importer,
            files: .standard,
            makeRecorder: { [settings] () -> RecorderEngine in
                #if os(macOS)
                // A microphone picked in Settings; if it is unplugged, the system default is used.
                if let uid = MicDevices.resolvedUID(saved: settings.inputDeviceUID) {
                    return DeviceRecorderEngine(deviceUID: uid)
                }
                #endif
                return AVAudioRecorderEngine()
            },
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
