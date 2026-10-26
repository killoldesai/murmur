import SwiftUI
import Observation
import WidgetKit
import MurmurCore

/// What the watch screens share: the recording, the outbox, the link to the iPhone, navigation.
@MainActor
@Observable
final class WatchSession {
    enum Route: Hashable {
        case recording
        case saved(UUID)
        case recent
        case playback(UUID)
    }

    let outbox: WatchOutbox
    let controller: WatchRecordingController
    let makePlayer: () -> PlayerEngine
    @ObservationIgnored private let link: WatchConnectivityLink?
    @ObservationIgnored private var recordWhenUnlocked = false

    var path: [Route] = []
    /// `nil` until the iPhone has answered.
    var isPro: Bool?
    var message: String?

    init(outbox: WatchOutbox, controller: WatchRecordingController, link: WatchConnectivityLink?, makePlayer: @escaping () -> PlayerEngine, isPro: Bool? = nil) {
        self.outbox = outbox
        self.controller = controller
        self.link = link
        self.makePlayer = makePlayer
        self.isPro = isPro
    }

    var isUnlocked: Bool { isPro == true }

    // MARK: Start

    func start() {
        outbox.removeMissingFiles()
        outbox.onChange = { [weak self] in self?.outboxChanged() }
        guard let link else { return }
        link.onTransferFinished = { [weak self] id, error in
            Task { @MainActor in self?.outbox.setDelivery(error == nil ? .delivered : .waiting, for: id) }
        }
        link.onProChanged = { [weak self] value in
            Task { @MainActor in self?.setPro(value) }
        }
        link.onActivated = { [weak self] in
            Task { @MainActor in self?.resendPending() }
        }
        link.activate()
        if let known = link.receivedIsPro { setPro(known) }
        outboxChanged()
    }

    private func setPro(_ value: Bool) {
        isPro = value
        if value, recordWhenUnlocked {
            recordWhenUnlocked = false
            Task { await beginRecording() }
        }
    }

    /// Tell the iPhone-side link to look again (the Locked screen's button).
    func recheck() {
        link?.activate()
        if let known = link?.receivedIsPro { setPro(known) }
    }

    // MARK: Recording

    func beginRecording() async {
        guard isUnlocked else { return }
        guard !controller.isRecording else {
            if path.last != .recording { path = [.recording] }
            return
        }
        await controller.start()
        if controller.state == .recording {
            path = [.recording]
        } else if case .failed(let text) = controller.state {
            message = text
        }
    }

    /// From a complication, the Action button or a `murmur://record` link. Waits for the iPhone's
    /// answer if the unlocked state is not known yet.
    func recordRequested() {
        if isUnlocked {
            Task { await beginRecording() }
        } else if isPro == nil {
            recordWhenUnlocked = true
        }
    }

    func stopRecording() {
        guard let transfer = controller.stop() else {
            path = []
            return
        }
        path = [.saved(transfer.id)]
        send(transfer.id)
    }

    func discardRecording() {
        controller.cancel()
        path = []
    }

    // MARK: Sending

    /// Queues every recording the iPhone does not have yet, unless Watch Connectivity already holds it.
    func resendPending() {
        guard let link else { return }
        let outstanding = link.outstandingIDs
        for entry in outbox.entries where entry.delivery != .delivered {
            if outstanding.contains(entry.id) {
                outbox.setDelivery(.sending, for: entry.id)
            } else {
                send(entry.id)
            }
        }
    }

    func send(_ id: UUID) {
        guard let entry = outbox.entry(id: id) else { return }
        guard let link else { return }
        link.send(entry.transfer, fileURL: outbox.audioURL(for: entry))
        outbox.setDelivery(.sending, for: id)
    }

    func delete(_ id: UUID) {
        outbox.delete(id: id)
    }

    private func outboxChanged() {
        WatchSnapshot.make(from: outbox).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
