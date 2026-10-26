import SwiftUI
import AVFoundation
import MurmurCore
import MurmurUI

/// Four steps: welcome, microphone, shortcut and menu bar, model download (design/mac/Onboarding.dc.html).
struct MacOnboardingView: View {
    let session: MacSession
    @State var step = 0
    @State private var micAllowed = AVAudioApplication.shared.recordPermission == .granted

    private let steps = ["Welcome", "Microphone", "Shortcut", "Model"]
    private var settings: AppSettings { session.deps.settings }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule().fill(index <= step ? MurmurTheme.Colors.accent : MurmurTheme.Colors.raised)
                        .frame(width: index == step ? 28 : 8, height: 8)
                }
            }
            .padding(.top, 36)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step + 1) of \(steps.count)")
            Spacer(minLength: 0)
            Group {
                switch step {
                case 0: welcome
                case 1: microphone
                case 2: shortcut
                default: MacModelDownloadView(manager: session.deps.models, onContinue: finish)
                }
            }
            .frame(maxWidth: 520)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MurmurTheme.Colors.background)
        .preferredColorScheme(.dark)
    }

    private func page<Extra: View>(symbol: String, title: String, body: String, @ViewBuilder extra: () -> Extra, primary: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(MurmurTheme.Colors.accent)
            Text(title).font(.system(size: 28, weight: .heavy)).foregroundStyle(MurmurTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(body).font(.system(size: 15)).foregroundStyle(MurmurTheme.Colors.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            extra()
            Button(action: action) {
                Text(primary).font(MurmurTheme.Mac.bodyBold).foregroundStyle(MurmurTheme.Colors.onAccent)
                    .padding(.horizontal, 28).frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 10).fill(MurmurTheme.Colors.accent))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var welcome: some View {
        page(symbol: "waveform.circle.fill", title: "Your words stay on your Mac",
             body: "Murmur turns meetings and lectures into text with Whisper, on this Mac. No servers, no accounts, nothing uploaded.",
             extra: { EmptyView() },
             primary: "Get started") { step = 1 }
    }

    private var microphone: some View {
        page(symbol: "mic.fill", title: "Let Murmur hear you",
             body: "Murmur records from the microphone so it can transcribe. Audio never leaves your Mac. You can also skip this and only import files.",
             extra: {
                 if micAllowed {
                     Label("Microphone allowed", systemImage: "checkmark.circle.fill")
                         .foregroundStyle(MurmurTheme.Colors.accent).font(MurmurTheme.Mac.bodyBold)
                 }
             },
             primary: micAllowed ? "Continue" : "Allow microphone") {
            if micAllowed {
                step = 2
            } else {
                Task {
                    await session.requestMicrophone()
                    micAllowed = AVAudioApplication.shared.recordPermission == .granted
                    step = 2
                }
            }
        }
    }

    private var shortcut: some View {
        page(symbol: "keyboard", title: "Record from anywhere",
             body: "Press the shortcut in any app to start and stop recording. Murmur also adds a menu bar item.",
             extra: {
                 VStack(spacing: 12) {
                     ShortcutRecorder(current: settings.recordShortcut) { settings.setRecordShortcut($0) }
                     Toggle("Show menu bar icon", isOn: Binding(get: { settings.showMenuBarIcon }, set: { settings.setShowMenuBarIcon($0) }))
                         .toggleStyle(.checkbox).font(MurmurTheme.Mac.body).foregroundStyle(MurmurTheme.Colors.textPrimary)
                 }
             },
             primary: "Continue") { step = 3 }
    }

    private func finish() {
        settings.completeOnboarding()
    }
}
