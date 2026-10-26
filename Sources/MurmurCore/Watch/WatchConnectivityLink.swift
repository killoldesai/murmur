import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity

/// Watch Connectivity on both sides.
///
/// Watch: `send` queues a file with `transferFile` (guaranteed, delivered when the iPhone is in
/// range); `onTransferFinished` reports each outcome; `isPro` comes from the iPhone's application context.
/// iPhone: `onFileReceived` gets each file (already copied somewhere safe); `publish(isPro:)` tells the watch.
public final class WatchConnectivityLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    /// iPhone: a recording arrived. The URL is a copy that stays valid after the callback.
    public var onFileReceived: (@Sendable (URL, WatchTransfer) -> Void)?
    /// Watch: a transfer finished (`nil` error) or failed.
    public var onTransferFinished: (@Sendable (UUID, Error?) -> Void)?
    /// Watch or iPhone: the session finished activating (outstanding transfers can be read now).
    public var onActivated: (@Sendable () -> Void)?
    /// Watch: the iPhone's answer to "is Pro unlocked?" changed.
    public var onProChanged: (@Sendable (Bool) -> Void)?

    private let inboxDirectory: URL

    public override init() {
        inboxDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("WatchInbox", isDirectory: true)
        super.init()
    }

    public func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: Watch side

    /// Ids of transfers WatchConnectivity still holds, so the app does not queue a file twice.
    public var outstandingIDs: Set<UUID> {
        guard WCSession.isSupported() else { return [] }
        return Set(WCSession.default.outstandingFileTransfers.compactMap { WatchTransfer(metadata: $0.file.metadata)?.id })
    }

    public func send(_ transfer: WatchTransfer, fileURL: URL) {
        guard WCSession.isSupported() else { return }
        WCSession.default.transferFile(fileURL, metadata: transfer.metadata)
    }

    /// Last answer from the iPhone, or `nil` if it has never answered.
    public var receivedIsPro: Bool? {
        guard WCSession.isSupported() else { return nil }
        return WCSession.default.receivedApplicationContext["isPro"] as? Bool
    }

    // MARK: iPhone side

    /// Tells the watch whether Pro is unlocked. Held until the session is active if it is not yet.
    public func publish(isPro: Bool) {
        pendingPro = isPro
        sendPendingPro()
    }

    private var pendingPro: Bool?

    private func sendPendingPro() {
        guard WCSession.isSupported(), let isPro = pendingPro else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        try? session.updateApplicationContext(["isPro": isPro])
    }

    // MARK: WCSessionDelegate

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        sendPendingPro()
        onActivated?()
        if let isPro = receivedIsPro { onProChanged?(isPro) }
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let isPro = applicationContext["isPro"] as? Bool { onProChanged?(isPro) }
    }

    public func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard let id = WatchTransfer(metadata: fileTransfer.file.metadata)?.id else { return }
        onTransferFinished?(id, error)
    }

    public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let transfer = WatchTransfer(metadata: file.metadata) else { return }
        // The system deletes `file.fileURL` when this method returns, so copy it first.
        try? FileManager.default.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)
        let copy = inboxDirectory.appendingPathComponent(transfer.fileName)
        try? FileManager.default.removeItem(at: copy)
        do {
            try FileManager.default.copyItem(at: file.fileURL, to: copy)
        } catch {
            return
        }
        onFileReceived?(copy, transfer)
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
#endif
