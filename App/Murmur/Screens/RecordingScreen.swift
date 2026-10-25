import SwiftUI
import MurmurCore
import MurmurUI

/// iPhone record screen. Matches design/iphone/Recording.dc.html.
struct RecordingScreen: View {
    let controller: RecordingController
    let onClose: () -> Void
    let onFinished: (Note) -> Void

    @State private var confirmDiscard = false

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

    private var content: some View {
        VStack(spacing: 0) {
            header
                .murmurEntrance(index: 0)

            VStack(spacing: 36) {
                RecordingOrb(
                    statusLabel: statusLabel,
                    time: Timecode.format(controller.elapsed),
                    isRunning: isRunning
                )
                .murmurEntrance(index: 1)

                Waveform(
                    levels: controller.levels.map { CGFloat($0) },
                    height: 96,
                    spacing: 4,
                    barWidth: 4
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
