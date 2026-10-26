import SwiftUI
import AppIntents
import MurmurCore
import MurmurUI

@main
struct MurmurWatchApp: App {
    @State private var session: WatchSession
    private let screen = UserDefaults.standard.string(forKey: "screen")
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let screen = UserDefaults.standard.string(forKey: "screen")
        _session = State(initialValue: screen == nil ? Self.makeLive() : Self.makeDemo(screen: screen!))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let screen {
                    WatchDemoRoot(session: session, screen: screen)
                } else {
                    WatchRoot(session: session)
                        .task { session.start() }
                        .onOpenURL { url in
                            if url.host == "record" { session.recordRequested() }
                        }
                }
            }
            .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            // The Action button runs StartRecordingIntent, which leaves a flag for the app.
            guard screen == nil, phase == .active else { return }
            if UserDefaults.standard.bool(forKey: StartRecordingIntent.flagKey) {
                UserDefaults.standard.set(false, forKey: StartRecordingIntent.flagKey)
                session.recordRequested()
            }
        }
    }

    private static func outboxDirectory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("WatchRecordings", isDirectory: true)
    }

    private static func makeLive() -> WatchSession {
        let outbox = WatchOutbox(directory: outboxDirectory())
        let controller = WatchRecordingController(engine: AACRecorderEngine(), outbox: outbox)
        return WatchSession(outbox: outbox, controller: controller, link: WatchConnectivityLink(), makePlayer: { AVAudioPlayerEngine() })
    }

    /// Screenshot mode (`-screen home|recording|saved|recent|playback|locked|complications`):
    /// a fake microphone, a few sample recordings, no Watch Connectivity.
    private static func makeDemo(screen: String) -> WatchSession {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-watch-demo-\(UUID().uuidString)", isDirectory: true)
        let outbox = WatchOutbox(directory: dir)
        let now = Date()
        let first = WatchTransfer(createdAt: now.addingTimeInterval(-60 * 5), duration: 58)
        let second = WatchTransfer(createdAt: now.addingTimeInterval(-3600 * 3), duration: 84)
        let third = WatchTransfer(createdAt: now.addingTimeInterval(-86_400 - 600), duration: 312)
        [third, second, first].forEach { outbox.add($0) }
        outbox.setDelivery(.delivered, for: second.id)
        outbox.setDelivery(.delivered, for: third.id)
        outbox.setDelivery(.sending, for: first.id)
        let controller = WatchRecordingController(engine: DemoRecorderEngine(), outbox: outbox)
        return WatchSession(outbox: outbox, controller: controller, link: nil,
                            makePlayer: { DemoPlayerEngine(duration: 84) }, isPro: screen != "locked")
    }
}

/// Demo screens, each as the root of the window.
struct WatchDemoRoot: View {
    @Bindable var session: WatchSession
    let screen: String

    var body: some View {
        Group {
            switch screen {
            case "recording":
                NavigationStack { WatchRecordingView(session: session) }
            case "saved":
                NavigationStack { WatchSavedView(session: session, id: session.outbox.entries.first?.id ?? UUID()) }
            case "recent":
                NavigationStack { WatchRecentView(session: session) }
            case "playback":
                NavigationStack { WatchPlaybackView(session: session, id: session.outbox.entries.dropFirst().first?.id ?? UUID()) }
            case "complications":
                WatchComplicationsPreview(snapshot: WatchSnapshot.make(from: session.outbox))
            default:
                WatchRoot(session: session)
            }
        }
        .background(MurmurTheme.Colors.watchBackground)
        .task {
            if screen == "recording" { await session.controller.start() }
        }
    }
}

/// Starts a recording from the Action button (Apple Watch Ultra) or Shortcuts.
struct StartRecordingIntent: AppIntent {
    static let flagKey = "watch.recordOnLaunch"
    static let title: LocalizedStringResource = "Record a memo"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: Self.flagKey)
        return .result()
    }
}

struct MurmurShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: ["Record a memo with \(.applicationName)"],
            shortTitle: "Record",
            systemImageName: "mic.fill"
        )
    }
}
