import SwiftUI
import SwiftData
import ServiceManagement
import UniformTypeIdentifiers
import MurmurCore
import MurmurUI

/// Preferences window: General, Transcription, Dictionary, Account (design/mac/Settings*.dc.html).
struct MacSettingsView: View {
    let session: MacSession
    @State var tab: Tab = .general

    enum Tab: String, CaseIterable, Identifiable {
        case general = "General", transcription = "Transcription", dictionary = "Dictionary", account = "Account"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .transcription: "waveform"
            case .dictionary: "character.book.closed"
            case .account: "person.crop.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Tab.allCases) { item in
                    Button { tab = item } label: {
                        VStack(spacing: 3) {
                            Image(systemName: item.symbol).font(.system(size: 16))
                            Text(item.rawValue).font(MurmurTheme.Mac.small)
                        }
                        .foregroundStyle(tab == item ? MurmurTheme.Colors.accent : MurmurTheme.Colors.textSecondary)
                        .frame(width: 92, height: 46)
                        .background(RoundedRectangle(cornerRadius: MurmurTheme.Mac.controlRadius).fill(tab == item ? MurmurTheme.Colors.selectedFill : .clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(MurmurTheme.Colors.panel)
            Rectangle().fill(MurmurTheme.Colors.border).frame(height: 1)
            Group {
                switch tab {
                case .general: MacGeneralSettings(session: session)
                case .transcription: MacTranscriptionSettings(session: session)
                case .dictionary: MacDictionarySettings(session: session)
                case .account: MacAccountSettings(session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 600, height: 460)
        .background(MurmurTheme.Colors.background)
        .preferredColorScheme(.dark)
    }
}

/// A labelled settings row: title and hint on the left, control on the right.
struct MacSettingRow<Control: View>: View {
    let title: String
    var hint: String?
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(MurmurTheme.Mac.body).foregroundStyle(MurmurTheme.Colors.textPrimary)
                if let hint { Text(hint).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textTertiary) }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(MurmurTheme.Colors.border).frame(height: 1) }
    }
}

struct MacGeneralSettings: View {
    let session: MacSession
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private var settings: AppSettings { session.deps.settings }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                MacSettingRow(title: "Open at login", hint: loginError) {
                    Toggle("", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)).labelsHidden()
                }
                MacSettingRow(title: "Show menu bar icon", hint: "Start and stop recording without opening the window.") {
                    Toggle("", isOn: Binding(get: { settings.showMenuBarIcon }, set: { value in
                        settings.setShowMenuBarIcon(value)
                        if !value { settings.setHideDockIcon(false); MacDockPolicy.apply(hidden: false) }
                    })).labelsHidden()
                }
                MacSettingRow(title: "Record shortcut", hint: "Works in any app. Needs Control, Option or Command.") {
                    ShortcutRecorder(current: settings.recordShortcut) { settings.setRecordShortcut($0) }
                }
                MacSettingRow(title: "Microphone", hint: "Recording uses this input. Unplugged devices fall back to the system default.") {
                    Picker("", selection: Binding(get: { settings.inputDeviceUID ?? "" }, set: { settings.setInputDeviceUID($0.isEmpty ? nil : $0) })) {
                        Text("System default").tag("")
                        ForEach(MicDevices.available()) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden().frame(width: 220)
                }
                MacSettingRow(title: "New notes go to", hint: "The folder for new recordings and imports.") {
                    Picker("", selection: Binding(get: { settings.defaultFolderID }, set: { settings.setDefaultFolderID($0) })) {
                        Text("No folder").tag(UUID?.none)
                        ForEach(folders) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .labelsHidden().frame(width: 180)
                }
                MacSettingRow(title: "Audio format", hint: settings.audioFormat.detail) {
                    Picker("", selection: Binding(get: { settings.audioFormat }, set: { settings.setAudioFormat($0) })) {
                        ForEach(AudioFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 120)
                }
                MacSettingRow(title: "Delete audio after transcribing", hint: "Saves space. The transcript stays.") {
                    Toggle("", isOn: Binding(get: { settings.deleteAudioAfterTranscribing }, set: { settings.setDeleteAudioAfterTranscribing($0) })).labelsHidden()
                }
                MacSettingRow(title: "Sync with iCloud", hint: settings.syncMessage) {
                    Toggle("", isOn: Binding(get: { settings.iCloudSyncEnabled }, set: { settings.setICloudSyncEnabled($0) })).labelsHidden()
                }
                MacSettingRow(title: "Hide Dock icon", hint: "Murmur lives in the menu bar. Needs the menu bar icon.") {
                    Toggle("", isOn: Binding(get: { settings.hideDockIcon }, set: { value in
                        settings.setHideDockIcon(value)
                        MacDockPolicy.apply(hidden: value)
                    })).labelsHidden().disabled(!settings.showMenuBarIcon)
                }
            }
            .padding(MurmurTheme.Mac.padding + 6)
            .toggleStyle(.switch)
            .tint(MurmurTheme.Colors.accent)
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "macOS didn’t allow that: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

enum MacDockPolicy {
    @MainActor static func apply(hidden: Bool) {
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
    }
}

struct ShortcutRecorder: View {
    let current: RecordShortcut
    let onChange: (RecordShortcut) -> Void
    @State private var listening = false
    @State private var monitor: Any?

    var body: some View {
        Button { listening ? stop() : start() } label: {
            Text(listening ? "Press the keys…" : current.display)
                .font(MurmurTheme.Mac.bodyBold)
                .foregroundStyle(listening ? MurmurTheme.Colors.accent : MurmurTheme.Colors.textPrimary)
                .frame(minWidth: 100).padding(.horizontal, 10).frame(height: MurmurTheme.Mac.controlHeight)
                .background(RoundedRectangle(cornerRadius: MurmurTheme.Mac.controlRadius).fill(MurmurTheme.Colors.surface))
                .overlay(RoundedRectangle(cornerRadius: MurmurTheme.Mac.controlRadius)
                    .strokeBorder(listening ? MurmurTheme.Colors.accent : MurmurTheme.Colors.border))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record shortcut, \(current.display)")
        .onDisappear { stop() }
    }

    private func start() {
        listening = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }   // Escape cancels
            let flags = event.modifierFlags
            var modifiers = 0
            if flags.contains(.control) { modifiers |= RecordShortcut.control }
            if flags.contains(.option) { modifiers |= RecordShortcut.option }
            if flags.contains(.shift) { modifiers |= RecordShortcut.shift }
            if flags.contains(.command) { modifiers |= RecordShortcut.command }
            let key = (event.charactersIgnoringModifiers ?? "").trimmingCharacters(in: .whitespaces)
            let shortcut = RecordShortcut(keyCode: Int(event.keyCode), carbonModifiers: modifiers, key: key)
            if shortcut.isValid {
                onChange(shortcut)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        listening = false
    }
}

struct MacTranscriptionSettings: View {
    let session: MacSession
    private var settings: AppSettings { session.deps.settings }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                MacSettingRow(title: "Language", hint: "Auto-detect works for most recordings.") {
                    Picker("", selection: Binding(get: { settings.language ?? "" }, set: { settings.setLanguage($0.isEmpty ? nil : $0) })) {
                        ForEach(TranscriptionLanguage.all, id: \.name) { language in
                            Text(language.name).tag(language.code ?? "")
                        }
                    }
                    .labelsHidden().frame(width: 180)
                }
                MacSettingRow(title: "Speech model", hint: modelHint) {
                    Picker("", selection: Binding(get: { session.deps.models.selected.id }, set: { id in
                        if let model = SpeechModel.model(withID: id) { session.deps.models.select(model) }
                    })) {
                        ForEach(SpeechModel.choices) { Text($0.title).tag($0.id) }
                    }
                    .labelsHidden().frame(width: 180).disabled(session.deps.models.isDownloading)
                }
                MacSettingRow(title: "Model status") {
                    HStack(spacing: 10) {
                        Text(statusText).font(MurmurTheme.Mac.body).foregroundStyle(MurmurTheme.Colors.textSecondary)
                        if session.deps.models.isReady {
                            Button("Remove") { session.deps.models.deleteSelected() }
                        } else if !session.deps.models.isDownloading {
                            Button("Download") { session.deps.models.start() }
                        }
                    }
                }
            }
            .padding(MurmurTheme.Mac.padding + 6)
        }
    }

    private var modelHint: String {
        let model = session.deps.models.selected
        return "\(model.subtitle) · \(ByteText.format(model.approximateBytes))"
    }

    private var statusText: String {
        switch session.deps.models.state {
        case .ready: "Ready"
        case .notDownloaded: "Not downloaded"
        case .downloading(let value): "Downloading \(Int(value * 100))%"
        case .failed: "Failed"
        }
    }
}

struct MacDictionarySettings: View {
    let session: MacSession
    @Query(sort: \DictionaryWord.createdAt, order: .reverse) private var words: [DictionaryWord]
    @State private var newWord = ""

    private var store: DictionaryStore { DictionaryStore(context: session.context) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Add a name or term", text: $newWord).textFieldStyle(.roundedBorder).onSubmit(add)
                Button("Add", action: add).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Button("Import…", action: importList)
                Button("Export…", action: exportList).disabled(words.isEmpty)
            }
            .padding(MurmurTheme.Mac.padding)
            HStack {
                Text("Word").frame(maxWidth: .infinity, alignment: .leading)
                Text("Type").frame(width: 80, alignment: .leading)
                Text("Added").frame(width: 100, alignment: .leading)
                Spacer().frame(width: 30)
            }
            .murmurSectionLabel().padding(.horizontal, MurmurTheme.Mac.padding).frame(height: 28)
            .background(MurmurTheme.Colors.panel)
            if words.isEmpty {
                Text("Add words Whisper often gets wrong, like names and jargon.")
                    .font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(words) { word in
                            HStack {
                                Text(word.term).font(MurmurTheme.Mac.body).foregroundStyle(MurmurTheme.Colors.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(word.kind == .name ? "Name" : "Term").font(MurmurTheme.Mac.small)
                                    .foregroundStyle(MurmurTheme.Colors.textSecondary).frame(width: 80, alignment: .leading)
                                Text(word.createdAt.formatted(.dateTime.month(.abbreviated).day())).font(MurmurTheme.Mac.small)
                                    .foregroundStyle(MurmurTheme.Colors.textTertiary).frame(width: 100, alignment: .leading)
                                Button { store.remove(word) } label: {
                                    Image(systemName: "minus.circle").foregroundStyle(MurmurTheme.Colors.textTertiary)
                                }
                                .buttonStyle(.plain).frame(width: 30).accessibilityLabel("Remove \(word.term)")
                            }
                            .padding(.horizontal, MurmurTheme.Mac.padding).frame(height: 34)
                            .overlay(alignment: .bottom) { Rectangle().fill(MurmurTheme.Colors.border).frame(height: 1) }
                        }
                    }
                }
            }
        }
    }

    private func add() {
        store.add(newWord)
        newWord = ""
    }

    private func importList() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        store.importList(text)
    }

    private func exportList() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Murmur dictionary.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? store.exportList().write(to: url, atomically: true, encoding: .utf8)
    }
}

struct MacAccountSettings: View {
    let session: MacSession
    private var entitlements: EntitlementController { session.deps.entitlements }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                MacSettingRow(title: entitlements.isPro ? "Murmur Pro" : "Free plan",
                              hint: entitlements.isPro ? "\(entitlements.activePlan?.title ?? "") plan · works on iPhone, iPad and Mac" : "The first 2 minutes of each note.") {
                    if !entitlements.isPro {
                        Button("Upgrade…") { session.showPaywall = true; NSApp.activate(ignoringOtherApps: true) }
                    } else {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(MurmurTheme.Colors.accent)
                    }
                }
                MacSettingRow(title: "Restore purchases", hint: "Uses your Apple ID.") {
                    Button("Restore") { Task { await entitlements.restore() } }
                }
                MacSettingRow(title: "Send feedback", hint: "Opens a form on GitHub.") { Link("Open", destination: LegalLinks.feedback) }
                MacSettingRow(title: "Privacy Policy") { Link("Open", destination: LegalLinks.privacy) }
                MacSettingRow(title: "Terms of Use") { Link("Open", destination: LegalLinks.terms) }
                MacSettingRow(title: "Your data", hint: session.deps.settings.isSyncActive
                              ? "Notes sync through your private iCloud. Audio stays on this Mac."
                              : "Audio and text never leave this Mac.") {
                    Image(systemName: "lock.fill").foregroundStyle(MurmurTheme.Colors.textTertiary)
                }
            }
            .padding(MurmurTheme.Mac.padding + 6)
        }
    }
}
