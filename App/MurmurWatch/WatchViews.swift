import SwiftUI
import MurmurCore
import MurmurUI

/// Root: Locked until the iPhone says Pro is unlocked, otherwise Home with a navigation stack.
struct WatchRoot: View {
    @Bindable var session: WatchSession

    var body: some View {
        Group {
            if session.isUnlocked {
                NavigationStack(path: $session.path) {
                    WatchHomeView(session: session)
                        .navigationDestination(for: WatchSession.Route.self) { route in
                            switch route {
                            case .recording: WatchRecordingView(session: session)
                            case .saved(let id): WatchSavedView(session: session, id: id)
                            case .recent: WatchRecentView(session: session)
                            case .playback(let id): WatchPlaybackView(session: session, id: id)
                            }
                        }
                }
            } else {
                WatchLockedView(session: session)
            }
        }
        .background(MurmurTheme.Colors.watchBackground)
    }
}

// MARK: - Shared bits

struct WatchCapsuleButton: View {
    let title: String
    var systemImage: String?
    var fill: Color = MurmurTheme.Colors.accent
    var textColor: Color = MurmurTheme.Colors.onAccent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(MurmurTheme.Watch.title)
            }
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, minHeight: MurmurTheme.Watch.buttonHeight)
            .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
    }
}

/// Delivery shown as a check (delivered) or a spinner (waiting or sending).
struct WatchDeliveryIcon: View {
    let delivery: WatchDelivery

    var body: some View {
        switch delivery {
        case .delivered:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(MurmurTheme.Colors.accent)
                .accessibilityLabel("Delivered")
        case .sending, .waiting:
            ProgressView().tint(MurmurTheme.Colors.textTertiary).scaleEffect(0.7)
                .accessibilityLabel(delivery == .sending ? "Sending" : "Waiting for iPhone")
        }
    }
}

// MARK: - 1 Home

struct WatchHomeView: View {
    @Bindable var session: WatchSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var waiting: Int { session.outbox.waitingCount }

    var body: some View {
        VStack(spacing: 10) {
            Button {
                Task { await session.beginRecording() }
            } label: {
                ZStack {
                    Circle().fill(MurmurTheme.Colors.record.opacity(0.25))
                        .frame(width: MurmurTheme.Watch.recordButtonSize + 14, height: MurmurTheme.Watch.recordButtonSize + 14)
                        .scaleEffect(pulse ? 1.06 : 0.94)
                    Circle().fill(MurmurTheme.Colors.record)
                        .frame(width: MurmurTheme.Watch.recordButtonSize, height: MurmurTheme.Watch.recordButtonSize)
                    Image(systemName: "mic.fill").font(.system(size: 34)).foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Record")
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
            }

            NavigationLink(value: WatchSession.Route.recent) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Recent").font(MurmurTheme.Watch.captionBold).foregroundStyle(MurmurTheme.Colors.textPrimary)
                        Text(waiting > 0 ? "\(waiting) waiting for iPhone" : (session.outbox.entries.isEmpty ? "No memos yet" : "All on iPhone"))
                            .font(MurmurTheme.Watch.caption).foregroundStyle(MurmurTheme.Colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MurmurTheme.Colors.textTertiary)
                }
                .padding(.horizontal, 12).frame(minHeight: MurmurTheme.Watch.buttonHeight)
                .background(RoundedRectangle(cornerRadius: MurmurTheme.Watch.cardRadius).fill(MurmurTheme.Colors.surface))
            }
            .buttonStyle(.plain)

            if let message = session.message {
                Text(message).font(MurmurTheme.Watch.caption).foregroundStyle(MurmurTheme.Colors.record)
            }
        }
        .navigationTitle("Murmur")
    }
}

// MARK: - 2 Recording

struct WatchRecordingView: View {
    @Bindable var session: WatchSession

    private var controller: WatchRecordingController { session.controller }
    private var paused: Bool { controller.state == .paused }

    var body: some View {
        VStack(spacing: 8) {
            Text(paused ? "Paused" : "Recording").font(MurmurTheme.Watch.captionBold)
                .foregroundStyle(paused ? MurmurTheme.Colors.textTertiary : MurmurTheme.Colors.record)
            Text(Timecode.format(controller.elapsed)).font(MurmurTheme.Watch.timer)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
            Waveform(levels: controller.levels.map { CGFloat($0) }, height: 26,
                     color: paused ? MurmurTheme.Colors.textTertiary : MurmurTheme.Colors.accent, spacing: 3, barWidth: 4)
            HStack(spacing: 8) {
                Button { controller.togglePause() } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .frame(width: 52, height: MurmurTheme.Watch.buttonHeight)
                        .background(Capsule().fill(MurmurTheme.Colors.raised))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(paused ? "Resume" : "Pause")
                WatchCapsuleButton(title: "Stop", systemImage: "stop.fill", fill: MurmurTheme.Colors.record, textColor: .white) {
                    session.stopRecording()
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - 3 Saved and sending

struct WatchCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.72))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.28))
        return path
    }
}

struct WatchSavedView: View {
    @Bindable var session: WatchSession
    let id: UUID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    private var entry: WatchRecordingEntry? { session.outbox.entry(id: id) }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(MurmurTheme.Colors.accent).frame(width: 50, height: 50)
                WatchCheckmark()
                    .trim(from: 0, to: drawn || reduceMotion ? 1 : 0)
                    .stroke(MurmurTheme.Colors.onAccent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .frame(width: 26, height: 26)
            }
            .onAppear {
                if reduceMotion { drawn = true } else { withAnimation(.easeOut(duration: 0.5).delay(0.15)) { drawn = true } }
            }
            Text("Saved · \(Timecode.format(entry?.transfer.duration ?? 0))").font(MurmurTheme.Watch.title)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
            HStack(spacing: 6) {
                WatchDeliveryIcon(delivery: entry?.delivery ?? .waiting)
                Text(statusText).font(MurmurTheme.Watch.caption).foregroundStyle(MurmurTheme.Colors.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            WatchCapsuleButton(title: "Done", fill: MurmurTheme.Colors.raised, textColor: MurmurTheme.Colors.textPrimary) {
                session.path = []
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private var statusText: String {
        switch entry?.delivery ?? .waiting {
        case .waiting: "Waiting for iPhone"
        case .sending: "Sending to iPhone"
        case .delivered: "On iPhone · transcribing"
        }
    }
}

// MARK: - 4 Recent

struct WatchRecentView: View {
    @Bindable var session: WatchSession

    var body: some View {
        let entries = session.outbox.recent(limit: 10)
        ScrollView {
            VStack(spacing: 6) {
                if entries.isEmpty {
                    Text("No memos yet").font(MurmurTheme.Watch.body).foregroundStyle(MurmurTheme.Colors.textSecondary)
                        .padding(.top, 20)
                }
                ForEach(entries) { entry in
                    NavigationLink(value: WatchSession.Route.playback(entry.id)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.title).font(MurmurTheme.Watch.captionBold).foregroundStyle(MurmurTheme.Colors.textPrimary)
                                Text(entry.meta()).font(MurmurTheme.Watch.caption).foregroundStyle(MurmurTheme.Colors.textSecondary)
                            }
                            Spacer(minLength: 0)
                            WatchDeliveryIcon(delivery: entry.delivery)
                        }
                        .padding(.horizontal, 12).frame(minHeight: MurmurTheme.Watch.buttonHeight)
                        .background(RoundedRectangle(cornerRadius: MurmurTheme.Watch.cardRadius).fill(MurmurTheme.Colors.surface))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Recent")
    }
}

// MARK: - 5 Playback

struct WatchPlaybackView: View {
    @Bindable var session: WatchSession
    let id: UUID
    @State private var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss

    init(session: WatchSession, id: UUID) {
        self.session = session
        self.id = id
        _playback = State(initialValue: PlaybackController(engine: session.makePlayer()))
    }

    private var entry: WatchRecordingEntry? { session.outbox.entry(id: id) }

    var body: some View {
        VStack(spacing: 6) {
            Text(entry?.title ?? "Memo").font(MurmurTheme.Watch.title).foregroundStyle(MurmurTheme.Colors.textPrimary)
            Text(entry?.meta() ?? "").font(MurmurTheme.Watch.caption).foregroundStyle(MurmurTheme.Colors.textSecondary)
            Button { playback.toggle() } label: {
                ZStack {
                    ProgressRing(progress: playback.progress, lineWidth: 6)
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 26))
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                }
                .frame(width: 84, height: 84)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            Text(playback.timeText).font(MurmurTheme.Watch.caption.monospacedDigit())
                .foregroundStyle(MurmurTheme.Colors.textSecondary)
            if playback.loadError != nil {
                Text("Audio isn’t on this watch").font(MurmurTheme.Watch.caption).foregroundStyle(MurmurTheme.Colors.record)
            }
        }
        .task {
            if let entry {
                playback.load(url: session.outbox.audioURL(for: entry), fallbackDuration: entry.transfer.duration)
                playback.start()
            }
        }
        .onDisappear { playback.stop() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    playback.stop()
                    session.delete(id)
                    dismiss()
                } label: { Image(systemName: "trash") }
                .accessibilityLabel("Delete memo")
            }
        }
    }
}

// MARK: - 6 Locked

struct WatchLockedView: View {
    @Bindable var session: WatchSession

    var body: some View {
        ScrollView {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill").font(.system(size: 28)).foregroundStyle(MurmurTheme.Colors.accent)
            Text("Unlock on iPhone").font(MurmurTheme.Watch.title).foregroundStyle(MurmurTheme.Colors.textPrimary)
            Text("Open Murmur on your iPhone to get Pro. Then record from your wrist.")
                .font(MurmurTheme.Watch.caption).foregroundStyle(MurmurTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            WatchCapsuleButton(title: "Check again", fill: MurmurTheme.Colors.raised, textColor: MurmurTheme.Colors.textPrimary) {
                session.recheck()
            }
        }
        .padding(.horizontal, 4)
        }
    }
}
