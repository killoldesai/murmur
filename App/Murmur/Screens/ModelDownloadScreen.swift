import SwiftUI
import MurmurCore
import MurmurUI

/// One-time speech model download. Matches design/iphone/ModelDownload.dc.html.
/// (The design says ≈1.6 GB for Large; the compressed Large v3 Turbo build is about 632 MB.)
struct ModelDownloadScreen: View {
    @Bindable var manager: SpeechModelManager
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDone: Bool { manager.state == .ready }
    private var fraction: Double {
        if case .downloading(let f) = manager.state { return f }
        return 0
    }
    private var failureMessage: String? {
        if case .failed(let message) = manager.state { return message }
        return nil
    }

    private var title: String {
        if isDone { return "You’re all set" }
        if manager.isDownloading { return "Downloading…" }
        if failureMessage != nil { return "Download didn’t finish" }
        return "Download the speech model"
    }

    private var message: String {
        if isDone { return "The model is on your iPhone. Recording and transcribing now work offline." }
        if manager.isDownloading { return "Keep Murmur open. This takes a few minutes on Wi‑Fi." }
        if let failureMessage { return failureMessage }
        return "One-time download. After this, Murmur works fully offline."
    }

    var body: some View {
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header.murmurEntrance(index: 0)

                VStack(spacing: 10) {
                    ForEach(Array(SpeechModel.choices.enumerated()), id: \.element.id) { index, model in
                        ModelOptionRow(
                            model: model,
                            isSelected: model == manager.selected,
                            isDimmed: model != manager.selected && (manager.isDownloading || isDone)
                        ) {
                            manager.select(model)
                        }
                        .disabled(manager.isDownloading || isDone)
                        .murmurEntrance(index: index + 1)
                    }
                }
                .padding(.top, 28)

                SettingsRow(systemImage: "wifi", title: "Download on Wi‑Fi only", isOn: $manager.wifiOnly)
                    .murmurCard()
                    .padding(.top, 14)
                    .disabled(manager.isDownloading)
                    .murmurEntrance(index: 3)

                Spacer(minLength: 24)

                footer
            }
            .padding(.horizontal, MurmurTheme.Metrics.screenPadding + 4)
            .padding(.top, 32)
            .padding(.bottom, 16)
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: isDone)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(MurmurTheme.Colors.surface)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth)
                Image(systemName: isDone ? "checkmark" : "arrow.down")
                    .font(.title.weight(.bold))
                    .foregroundStyle(MurmurTheme.Colors.accent)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, isActive: manager.isDownloading && !reduceMotion)
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)

            Text(title)
                .font(MurmurTheme.Fonts.title)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(MurmurTheme.Fonts.body)
                .foregroundStyle(MurmurTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            if manager.isDownloading {
                VStack(spacing: 8) {
                    HStack {
                        Text("\(ByteText.format(Int64(Double(manager.selected.approximateBytes) * fraction))) of \(ByteText.format(manager.selected.approximateBytes))")
                        Spacer()
                        Text("\(Int(fraction * 100))%")
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)

                    ProgressBar(fraction: fraction)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Download progress")
                .accessibilityValue("\(Int(fraction * 100)) percent")
                SecondaryButton("Cancel") { manager.cancel() }
            } else if isDone {
                PrimaryButton("Start using Murmur", action: onContinue)
            } else if failureMessage != nil {
                PrimaryButton("Try again") { manager.start() }
            } else {
                PrimaryButton("Download model") { manager.start() }
            }
            Text("You can switch models anytime in Settings.")
                .font(MurmurTheme.Fonts.caption)
                .foregroundStyle(MurmurTheme.Colors.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct ModelOptionRow: View {
    let model: SpeechModel
    let isSelected: Bool
    let isDimmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? MurmurTheme.Colors.accent : MurmurTheme.Colors.textTertiary, lineWidth: 2)
                    if isSelected {
                        Circle().fill(MurmurTheme.Colors.accent).padding(5)
                    }
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(model.title)
                            .font(MurmurTheme.Fonts.headline)
                            .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        if model.isRecommended {
                            Text("RECOMMENDED")
                                .font(.system(.caption2, weight: .heavy))
                                .tracking(0.6)
                                .foregroundStyle(MurmurTheme.Colors.onAccent)
                                .padding(.horizontal, 8)
                                .frame(height: 20)
                                .background(Capsule().fill(MurmurTheme.Colors.accent))
                        }
                    }
                    Text(model.subtitle)
                        .font(.footnote)
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                }
                Spacer(minLength: 8)
                Text("≈" + ByteText.format(model.approximateBytes))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .murmurCard(selected: isSelected)
            .opacity(isDimmed ? 0.45 : 1)
            .animation(.easeOut(duration: 0.25), value: isSelected)
        }
        .buttonStyle(MurmurPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(MurmurTheme.Colors.raised)
                Capsule()
                    .fill(MurmurTheme.Colors.accent)
                    .frame(width: proxy.size.width * min(1, max(0, fraction)))
                    .animation(.linear(duration: 0.3), value: fraction)
            }
        }
        .frame(height: 8)
    }
}
