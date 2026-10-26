import SwiftUI
import SwiftData
import MurmurCore
import MurmurUI

/// Chooses what the main window shows. Launch arguments let CI screenshot specific screens:
///   `-screen main|noteLocked|queue|drop|export|paywall|recording|menubar|settings|dictionary|account|onboarding|onboardingMic|onboardingShortcut|onboardingModel`
///   `-snapshot <file.png>`   write the window to a PNG a few seconds after launch, then quit
/// With no `-screen` the app behaves normally.
struct MacRoot: View {
    let session: MacSession
    let screen: String?

    var body: some View {
        framed(content)
            .modifier(OpenerIfLive(session: session, live: screen == nil))
            .task { await prepare() }
            .onOpenURL { session.importFiles([$0]) }
    }

    /// Demo screens get a fixed size so the snapshot is the right shape.
    @ViewBuilder private func framed(_ view: some View) -> some View {
        switch screen {
        case nil: view
        case "recording": view.frame(width: 340, height: 230)
        case "menubar": view.fixedSize()
        case "settings", "dictionary", "account": view.frame(width: 600, height: 460)
        case "export": view.frame(width: 520, height: 420)
        case "paywall": view.frame(width: 730, height: 560)
        case "onboarding", "onboardingMic", "onboardingShortcut", "onboardingModel": view.frame(width: 900, height: 600)
        default: view.frame(width: 1180, height: 760)
        }
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case nil:
            if session.deps.settings.hasCompletedOnboarding {
                MacMainView(session: session)
            } else {
                MacOnboardingView(session: session)
            }
        case "main", "noteLocked", "queue", "drop":
            MacMainView(session: session)
        case "export":
            ExportDemo(session: session)
        case "paywall":
            MacPaywallView(entitlements: session.deps.entitlements, onClose: {})
        case "recording":
            if let recorder = session.recorder {
                RecorderPanel(recorder: recorder, onStop: {}, onDiscard: {})
                    .background(MurmurTheme.Colors.background)
            } else {
                MurmurTheme.Colors.background
            }
        case "menubar":
            MenuBarDemo(session: session)
        case "settings":
            MacSettingsView(session: session)
        case "dictionary":
            MacSettingsView(session: session, tab: .dictionary)
        case "account":
            MacSettingsView(session: session, tab: .account)
        case "onboardingMic":
            MacOnboardingView(session: session, step: 1)
        case "onboardingShortcut":
            MacOnboardingView(session: session, step: 2)
        case "onboardingModel":
            MacOnboardingView(session: session, step: 3)
        default:
            MacOnboardingView(session: session)
        }
    }

    /// Demo setup that must not run in `init`: pick the note, open sheets, then take the snapshot.
    private func prepare() async {
        if screen == nil {
            await session.deps.entitlements.start()
            if session.deps.models.isReady { session.deps.queue.start() }
            return
        }
        switch screen {
        case "main", "noteLocked":
            session.selectedNoteID = DemoData.firstReadyNoteID(in: session.container)
        case "queue":
            session.sidebar = .queue
            _ = session.deps.importer.enqueue([URL(fileURLWithPath: "/tmp/Customer call.m4a"), URL(fileURLWithPath: "/tmp/Lecture 9.mp3"), URL(fileURLWithPath: "/tmp/Standup.wav")])
        case "drop":
            session.selectedNoteID = DemoData.firstReadyNoteID(in: session.container)
            session.dropCount = 3
            session.isDropTargeted = true
        case "recording", "menubar":
            session.startRecording()
        default:
            break
        }
        if screen == "recording" { try? await Task.sleep(nanoseconds: 1_200_000_000) }
        if let path = UserDefaults.standard.string(forKey: "snapshot") {
            await SnapshotWriter.write(to: path, after: screen == "recording" ? 2 : 4)
        }
    }
}

/// Opens the floating recorder when a recording starts. Off in screenshot mode.
private struct OpenerIfLive: ViewModifier {
    let session: MacSession
    let live: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if live { content.modifier(RecorderWindowOpener(session: session)) } else { content }
    }
}

private struct ExportDemo: View {
    let session: MacSession
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    var body: some View {
        if let note = notes.first(where: { $0.status == .ready }) {
            MacExportSheet(note: note, session: session)
        }
    }
}

private struct MenuBarDemo: View {
    let session: MacSession
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    var body: some View {
        MenuBarContent(session: session, recent: Array(notes.prefix(4)))
    }
}

/// Writes the main window to a PNG, then quits. Only used by CI screenshots.
@MainActor
enum SnapshotWriter {
    private static func say(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    static func write(to path: String, after seconds: Double) async {
        say("snapshot: waiting \(seconds)s, windows now: \(NSApp.windows.count)")
        // No App Nap: a window that is not frontmost must still run its timers.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "snapshot")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { continuation.resume() }
        }
        say("snapshot: woke up")
        for window in NSApp.windows {
            say("window \(window.title) visible=\(window.isVisible) frame=\(window.frame) content=\(window.contentView != nil)")
        }
        guard let window = NSApp.windows.first(where: { $0.contentView != nil && $0.frame.width > 100 }), let view = window.contentView else {
            say("snapshot: no window")
            exit(2)
        }
        var data: Data?
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            data = rep.representation(using: .png, properties: [:])
        }
        guard let png = data else {
            say("snapshot: could not draw")
            exit(3)
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            say("snapshot: wrote \(path) (\(png.count) bytes)")
        } catch {
            say("snapshot: write failed \(error)")
            exit(4)
        }
        exit(0)
    }
}
