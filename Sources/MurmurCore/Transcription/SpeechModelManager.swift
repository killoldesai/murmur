import Foundation
import Observation

public enum SpeechModelState: Equatable, Sendable {
    case notDownloaded
    case downloading(Double)
    case ready
    case failed(String)
}

public protocol SpeechModelDownloader: Sendable {
    /// Downloads `model` and returns the folder that holds it. `onProgress` reports 0...1 and
    /// may be called from any thread.
    func download(_ model: SpeechModel, onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL
}

public enum SpeechModelManagerError: Error, Equatable {
    case wifiRequired
}

/// Owns which model is selected, whether it is on disk, and the download itself.
@MainActor
@Observable
public final class SpeechModelManager {
    public private(set) var state: SpeechModelState = .notDownloaded
    public private(set) var selected: SpeechModel
    public var wifiOnly: Bool {
        didSet { defaults.set(wifiOnly, forKey: Keys.wifiOnly) }
    }

    private let downloader: SpeechModelDownloader
    private let baseDirectory: URL
    private let defaults: UserDefaults
    private let isOnExpensiveNetwork: @MainActor () -> Bool
    private var task: Task<Void, Never>?
    /// Bumped on every start and cancel so a stale download can never touch the state.
    private var generation = 0

    private enum Keys {
        static let wifiOnly = "model.wifiOnly"
        static let selected = "model.selected"
        static func folder(_ id: String) -> String { "model.folder.\(id)" }
    }

    public init(
        downloader: SpeechModelDownloader,
        baseDirectory: URL,
        defaults: UserDefaults = .standard,
        isOnExpensiveNetwork: @escaping @MainActor () -> Bool = { false }
    ) {
        self.downloader = downloader
        self.baseDirectory = baseDirectory
        self.defaults = defaults
        self.isOnExpensiveNetwork = isOnExpensiveNetwork
        self.wifiOnly = defaults.object(forKey: Keys.wifiOnly) as? Bool ?? true
        let id = defaults.string(forKey: Keys.selected) ?? SpeechModel.large.id
        self.selected = SpeechModel.model(withID: id) ?? .large
        refresh()
    }

    public var isReady: Bool { state == .ready }

    /// Folder of the selected model when it is downloaded and still on disk.
    public var readyFolder: URL? {
        guard let url = storedFolder(for: selected), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    public var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    public func select(_ model: SpeechModel) {
        guard !isDownloading else { return }
        selected = model
        defaults.set(model.id, forKey: Keys.selected)
        refresh()
    }

    public func start() {
        guard !isDownloading, !isReady else { return }
        if wifiOnly && isOnExpensiveNetwork() {
            state = .failed("You're on mobile data. Connect to Wi‑Fi, or turn off “Download on Wi‑Fi only”.")
            return
        }
        generation += 1
        let gen = generation
        let model = selected
        state = .downloading(0)
        task = Task { [downloader] in
            do {
                let folder = try await downloader.download(model) { fraction in
                    Task { @MainActor [weak self] in self?.report(fraction, generation: gen) }
                }
                self.finish(model: model, folder: folder, generation: gen)
            } catch {
                self.fail(error, generation: gen)
            }
        }
    }

    public func cancel() {
        guard isDownloading else { return }
        generation += 1
        task?.cancel()
        state = .notDownloaded
    }

    /// Removes the selected model from disk.
    public func deleteSelected() {
        if let url = storedFolder(for: selected) {
            try? FileManager.default.removeItem(at: url)
        }
        defaults.removeObject(forKey: Keys.folder(selected.id))
        state = .notDownloaded
    }

    // MARK: - Internals

    private func refresh() {
        state = readyFolder != nil ? .ready : .notDownloaded
    }

    private func report(_ fraction: Double, generation gen: Int) {
        guard gen == generation, case .downloading(let current) = state else { return }
        let clamped = min(1, max(0, fraction))
        if clamped > current { state = .downloading(clamped) }
    }

    private func finish(model: SpeechModel, folder: URL, generation gen: Int) {
        guard gen == generation else { return }
        defaults.set(relativePath(of: folder), forKey: Keys.folder(model.id))
        refresh()
    }

    private func fail(_ error: Error, generation gen: Int) {
        guard gen == generation else { return }
        state = .failed("Download failed: \(error.localizedDescription). Check your connection and try again.")
    }

    /// Paths are stored relative to the base directory because the app container's absolute
    /// path can change between launches and updates.
    private func relativePath(of url: URL) -> String {
        let base = baseDirectory.resolvingSymlinksInPath().path
        let full = url.resolvingSymlinksInPath().path
        if full.hasPrefix(base + "/") { return String(full.dropFirst(base.count + 1)) }
        return full
    }

    private func storedFolder(for model: SpeechModel) -> URL? {
        guard let stored = defaults.string(forKey: Keys.folder(model.id)) else { return nil }
        if stored.hasPrefix("/") { return URL(fileURLWithPath: stored) }
        return baseDirectory.appendingPathComponent(stored, isDirectory: true)
    }
}
