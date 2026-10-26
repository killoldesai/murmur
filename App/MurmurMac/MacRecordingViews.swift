import SwiftUI
import AVFoundation
import MurmurCore
import MurmurUI

/// The name of the microphone Murmur records from (the system's default input).
enum InputDevice {
    static var name: String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? "Default microphone"
    }
}

/// Small floating recorder (design/mac/Recording.dc.html): timer, waveform, bookmark, pause, stop.
struct MacRecordingWindow: View {
    @Bindable var session: MacSession
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let recorder = session.recorder {
                RecorderPanel(recorder: recorder,
                              onStop: { session.stopRecording(); dismissWindow(id: "recorder") },
                              onDiscard: { session.cancelRecording(); dismissWindow(id: "recorder") })
            } else {
                Text("Not recording").font(MurmurTheme.Mac.body).foregroundStyle(MurmurTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { dismissWindow(id: "recorder") }
            }
        }
        .frame(width: 340, height: 230)
        .background(MurmurTheme.Colors.background)
        .background(WindowAccessor { window in
            window.level = .floating
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
        })
        .preferredColorScheme(.dark)
    }
}

struct RecorderPanel: View {
    @Bindable var recorder: RecordingController
    let onStop: () -> Void
    let onDiscard: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var paused: Bool { recorder.state == .paused }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(paused ? MurmurTheme.Colors.textTertiary : MurmurTheme.Colors.record).frame(width: 9, height: 9)
                Text(paused ? "Paused" : "Recording").font(MurmurTheme.Mac.smallBold)
                    .foregroundStyle(paused ? MurmurTheme.Colors.textTertiary : MurmurTheme.Colors.record)
                Spacer()
                Label(InputDevice.name, systemImage: "mic").font(MurmurTheme.Mac.small)
                    .foregroundStyle(MurmurTheme.Colors.textTertiary).lineLimit(1)
            }
            Text(Timecode.format(recorder.elapsed)).font(MurmurTheme.Mac.timer)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
            Waveform(levels: recorder.levels.map { CGFloat($0) }, height: 36,
                     color: paused ? MurmurTheme.Colors.textTertiary : MurmurTheme.Colors.accent, spacing: 2, barWidth: 4)
            if case .failed(let message) = recorder.state {
                Text(message).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.record).lineLimit(2)
            }
            HStack(spacing: 10) {
                roundButton("bookmark", label: "Add bookmark", badge: recorder.bookmarkCount) { recorder.addBookmark() }
                roundButton(paused ? "play.fill" : "pause.fill", label: paused ? "Resume" : "Pause", badge: 0) { recorder.togglePause() }
                Button(action: onStop) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                        Text("Stop").font(MurmurTheme.Mac.bodyBold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: 36)
                    .background(Capsule().fill(MurmurTheme.Colors.record))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Stop recording")
                roundButton("trash", label: "Discard recording", badge: 0, action: onDiscard)
            }
        }
        .padding(18)
    }

    private func roundButton(_ symbol: String, label: String, badge: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: symbol).foregroundStyle(MurmurTheme.Colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(MurmurTheme.Colors.surface))
                    .overlay(Circle().strokeBorder(MurmurTheme.Colors.border))
                if badge > 0 {
                    Text("\(badge)").font(.system(size: 9, weight: .bold)).foregroundStyle(MurmurTheme.Colors.onAccent)
                        .padding(.horizontal, 4).background(Capsule().fill(MurmurTheme.Colors.accent))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Gives SwiftUI access to the hosting `NSWindow`.
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { configure(window) } }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { if let window = view.window { configure(window) } }
    }
}

// MARK: - Menu bar

/// The label in the menu bar: a waveform icon, or the running timer while recording.
struct MenuBarLabel: View {
    let session: MacSession
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let recorder = session.recorder, session.isRecording {
                Label(Timecode.format(recorder.elapsed), systemImage: "record.circle.fill")
            } else {
                Image(systemName: "waveform")
            }
        }
        .modifier(RecorderWindowOpener(session: session))
    }
}

/// Opens the floating recorder when a recording starts, from any entry point.
struct RecorderWindowOpener: ViewModifier {
    let session: MacSession
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onChange(of: session.recorder != nil) { _, recording in
            if recording { openWindow(id: "recorder") }
        }
    }
}

/// Dropdown (design/mac/MenuBar.dc.html).
struct MenuBarContent: View {
    @Bindable var session: MacSession
    let recent: [Note]
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let recorder = session.recorder, session.isRecording {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle().fill(MurmurTheme.Colors.record).frame(width: 8, height: 8)
                        Text(Timecode.format(recorder.elapsed)).font(.system(size: 20, weight: .light).monospacedDigit())
                            .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        Spacer()
                    }
                    Waveform(levels: recorder.levels.map { CGFloat($0) }, height: 22, spacing: 2, barWidth: 3)
                }
                .padding(10)
                item("Stop recording", "stop.fill", tint: MurmurTheme.Colors.record) { session.stopRecording() }
            } else {
                item("Start recording", "mic.fill", detail: session.deps.settings.recordShortcut.display, tint: MurmurTheme.Colors.accent) {
                    session.startRecording()
                }
            }
            Label(InputDevice.name, systemImage: "mic").font(MurmurTheme.Mac.small)
                .foregroundStyle(MurmurTheme.Colors.textTertiary).padding(.horizontal, 10).padding(.vertical, 4)
            divider
            Text("Recent").murmurSectionLabel().padding(.horizontal, 10).padding(.top, 4)
            if recent.isEmpty {
                Text("No notes yet").font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textTertiary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
            }
            ForEach(recent.prefix(4)) { note in
                item(note.title, "doc.text", detail: Timecode.format(note.duration)) {
                    session.select(note)
                    show()
                }
            }
            divider
            item("Open Murmur", "macwindow") { show() }
            item("Import files…", "square.and.arrow.down") { show(); session.sidebar = .queue }
            item("Settings…", "gearshape") { NSApp.activate(ignoringOtherApps: true); openSettings() }
            divider
            item("Quit Murmur", "power") { NSApp.terminate(nil) }
        }
        .padding(8)
        .frame(width: 280)
        .background(MurmurTheme.Colors.panel)
    }

    private var divider: some View {
        Rectangle().fill(MurmurTheme.Colors.border).frame(height: 1).padding(.vertical, 4)
    }

    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }

    private func item(_ title: String, _ symbol: String, detail: String? = nil, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 18).foregroundStyle(tint ?? MurmurTheme.Colors.textSecondary)
                Text(title).font(MurmurTheme.Mac.body).foregroundStyle(MurmurTheme.Colors.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
                if let detail { Text(detail).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textTertiary) }
            }
            .padding(.horizontal, 10).frame(height: MurmurTheme.Mac.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
