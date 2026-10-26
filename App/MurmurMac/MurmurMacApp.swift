import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import MurmurCore
import MurmurUI

@main
struct MurmurMacApp: App {
    private let container: ModelContainer
    private let session: MacSession
    private let services: AppServices?
    private let screen: String?
    private let hotKey = GlobalHotKey()
    @AppStorage("settings.showMenuBarIcon") private var showMenuBarIcon = true

    init() {
        let screen = UserDefaults.standard.string(forKey: "screen")
        self.screen = screen
        if screen != nil {
            // Screenshot mode: demo notes, fake microphone, fake downloader. Nothing real is touched.
            let container = DemoData.makeContainer(seeded: screen != "empty")
            self.container = container
            self.services = nil
            self.session = MacSession(deps: DemoData.dependencies(container: container), container: container)
        } else {
            let container: ModelContainer
            do {
                container = try MurmurSchema.makeContainer()
            } catch {
                fatalError("Could not create the Murmur data store: \(error)")
            }
            let services = AppServices(container: container)
            self.container = container
            self.services = services
            self.session = MacSession(
                deps: services.libraryDependencies,
                container: container,
                requestMicrophone: { await services.requestMicrophone() }
            )
        }
    }

    var body: some Scene {
        Window("Murmur", id: "main") {
            MacRoot(session: session, screen: screen)
                .modelContainer(container)
                .frame(minWidth: screen == nil ? 980 : 0, minHeight: screen == nil ? 620 : 0)
                .task { await applyLaunchSettings() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .windowResizability(screen == nil ? .automatic : .contentSize)
        .commands { MacCommands(session: session) }

        Window("Recording", id: "recorder") {
            MacRecordingWindow(session: session)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        MenuBarExtra(isInserted: Binding(get: { showMenuBarIcon && screen == nil }, set: { showMenuBarIcon = $0 })) {
            MenuBarHost(session: session).modelContainer(container)
        } label: {
            MenuBarLabel(session: session)
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsView(session: session).modelContainer(container)
        }
    }

    /// Registers the global shortcut and applies the Dock setting. Skipped in screenshot mode.
    @MainActor private func applyLaunchSettings() async {
        guard screen == nil else { return }
        let settings = session.deps.settings
        if settings.hideDockIcon { MacDockPolicy.apply(hidden: true) }
        let session = self.session
        var registered = settings.recordShortcut
        hotKey.register(registered) { Task { @MainActor in session.toggleRecording() } }
        // The shortcut can change in Settings; keep the system hot key in step with it.
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if settings.recordShortcut != registered {
                registered = settings.recordShortcut
                hotKey.register(registered) { Task { @MainActor in session.toggleRecording() } }
            }
        }
    }
}

private struct MenuBarHost: View {
    let session: MacSession
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    var body: some View {
        MenuBarContent(session: session, recent: Array(notes.prefix(4)))
    }
}

/// File, Edit, View and Note menu items with their shortcuts.
struct MacCommands: Commands {
    let session: MacSession

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Recording") { session.startRecording() }
                .keyboardShortcut("n")
            Button("Import Audio or Video…") { importWithPanel() }
                .keyboardShortcut("o")
        }
        CommandGroup(after: .textEditing) {
            Button("Find") { session.focusSearch() }
                .keyboardShortcut("f")
        }
        CommandGroup(after: .sidebar) {
            Button(session.showInspector ? "Hide Inspector" : "Show Inspector") { session.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
        CommandMenu("Note") {
            Button("Export…") {
                if let note = session.selectedNote { session.requestExport(note) }
            }
            .keyboardShortcut("e")
            Button("Stop Recording") { session.stopRecording() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!session.isRecording)
        }
    }

    private func importWithPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie]
        panel.prompt = "Import"
        if panel.runModal() == .OK { session.importFiles(panel.urls) }
    }
}
