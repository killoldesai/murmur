import SwiftUI
import MurmurCore
import MurmurUI

/// iPhone record screen. Matches design/iphone/Recording.dc.html.
struct RecordingScreen: View {
    let controller: RecordingController
    let onClose: () -> Void
    let onFinished: (Note) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var confirmDiscard = false

    private var isPad: Bool { sizeClass == .regular }

    private var isRunning: Bool { controller.state == .recording }
    private var isPaused: Bool { controller.state == .paused }

    private var statusLabel: String {
        switch controller.state {
        case .recording: "Recording"
        case .paused: "Paused"
        default: "Starting"
        }
    }

    var body: some View {
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
            if case .failed(let message) = controller.state {
                failedView(message)
            } else {
                content
            }
        }
        .preferredColorScheme(.dark)
        .task { await controller.start() }
        .confirmationDialog("Discard this recording?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard recording", role: .destructive) {
                controller.cancel()
                onClose()
            }
            Button("Keep recording", role: .cancel) {}
        }
        .sensoryFeedback(.impact, trigger: controller.bookmarkCount)
    }

    @ViewBuilder
    private var content: some View {
        if isPad {
            HStack(spacing: 0) {
                mainColumn
                bookmarksPanel
            }
        } else {
            mainColumn
        }
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            header
                .murmurEntrance(index: 0)

            VStack(spacing: isPad ? 40 : 36) {
                if isPad {
                    padTimer.murmurEntrance(index: 1)
                } else {
                    RecordingOrb(
                        statusLabel: statusLabel,
                        time: Timecode.format(controller.elapsed),
                        isRunning: isRunning
                    )
                    .murmurEntrance(index: 1)
                }

                Waveform(
                    levels: controller.levels.map { CGFloat($0) },
                    height: isPad ? 150 : 96,
                    spacing: isPad ? 5 : 4,
                    barWidth: isPad ? 5 : 4
                )
                .opacity(isPaused ? 0.3 : 1)
                .animation(.easeInOut(duration: 0.4), value: isPaused)
                .murmurEntrance(index: 2)
            }
            .frame(maxHeight: .infinity)

            controls
                .murmurEntrance(index: 3)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    /// Large timer used on iPad (design/ipad/Recording.dc.html).
    private var padTimer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isRunning ? MurmurTheme.Colors.record : MurmurTheme.Colors.textSecondary)
                    .frame(width: 8, height: 8)
                Text(statusLabel)
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(isRunning ? MurmurTheme.Colors.record : MurmurTheme.Colors.textSecondary)
            }
            Text(Timecode.format(controller.elapsed))
                .font(.system(size: 96, weight: .ultraLight).monospacedDigit())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
            Text("New recording")
                .font(MurmurTheme.Fonts.body)
                .foregroundStyle(MurmurTheme.Colors.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(statusLabel), \(Timecode.format(controller.elapsed))")
    }

    /// Bookmarks fill in as moments are marked.
    private var bookmarksPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bookmarks")
                .font(MurmurTheme.Fonts.headline)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Tap the bookmark button to mark a moment. Jump back to it from the transcript.")
                .font(.subheadline)
                .foregroundStyle(MurmurTheme.Colors.textSecondary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(controller.bookmarks.enumerated()), id: \.offset) { index, time in
                        HStack(spacing: 12) {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(MurmurTheme.Colors.folder(1))
                            Text(Timecode.format(time))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                            Text("Bookmark \(index + 1)")
                                .font(.subheadline)
                                .foregroundStyle(MurmurTheme.Colors.textSecondary)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
                        .murmurCard()
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Spacer(minLength: 0)
            Text("Saved as you record. Recording continues if you switch apps or lock the screen.")
                .font(.footnote)
                .foregroundStyle(MurmurTheme.Colors.textSecondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .murmurCard()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 32)
        .frame(width: 340)
        .background(MurmurTheme.Colors.panel)
        .overlay(alignment: .leading) {
            Rectangle().fill(MurmurTheme.Colors.border).frame(width: MurmurTheme.Metrics.borderWidth)
        }
    }

    private var header: some View {
        HStack {
            Button {
                if controller.elapsed > 3 {
                    confirmDiscard = true
                } else {
                    controller.cancel()
                    onClose()
                }
            } label: {
                Text("Cancel")
                    .font(MurmurTheme.Fonts.body)
                    .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
                    .background(Capsule().fill(MurmurTheme.Colors.surface))
                    .overlay(Capsule().strokeBorder(MurmurTheme.Colors.border, lineWidth: 1))
            }
            .buttonStyle(MurmurPressStyle())

            Spacer()
            StatusPill("Private · Offline", systemImage: "lock")
        }
    }

    private var controls: some View {
        HStack(spacing: 30) {
            RoundControlButton(systemImage: "bookmark", label: "Add bookmark") {
                controller.addBookmark()
            }
            StopButton(isRunning: isRunning) {
                if let note = controller.stop() {
                    onFinished(note)
                }
            }
            RoundControlButton(
                systemImage: isPaused ? "play.fill" : "pause.fill",
                label: isPaused ? "Resume" : "Pause",
                isAccent: isPaused
            ) {
                controller.togglePause()
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(Capsule().fill(MurmurTheme.Colors.surface))
        .overlay(Capsule().strokeBorder(MurmurTheme.Colors.border, lineWidth: 1))
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "mic.slash")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(MurmurTheme.Colors.record)
            Text("Can't record")
                .font(MurmurTheme.Fonts.title)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
            Text(message)
                .font(MurmurTheme.Fonts.body)
                .foregroundStyle(MurmurTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            PrimaryButton("Open Settings", systemImage: "gearshape") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            SecondaryButton("Close") {
                controller.cancel()
                onClose()
            }
        }
        .padding(MurmurTheme.Metrics.screenPadding)
    }
}
