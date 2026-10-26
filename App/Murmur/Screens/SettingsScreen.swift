import SwiftUI
import SwiftData
import UIKit
import MurmurCore
import MurmurUI

/// Settings. Matches design/iphone/Settings.dc.html.
struct SettingsScreen: View {
    let deps: LibraryDependencies

    @Environment(\.dismiss) private var dismiss
    @Query private var words: [DictionaryWord]
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var pane: Pane = .transcription
    @State private var showPaywall = false

    private var settings: AppSettings { deps.settings }
    private var entitlements: EntitlementController { deps.entitlements }

    var body: some View {
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
            if sizeClass == .regular {
                padLayout
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        HeaderCircleButton(symbol: "chevron.left", label: "Back to library") { dismiss() }
                        Spacer()
                    }
                    .padding(.top, 8)
                    Text("Settings")
                        .font(MurmurTheme.Fonts.largeTitle)
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    proCard.murmurEntrance(index: 0)

                    group("Transcription") {
                        transcriptionRows
                    }
                    .murmurEntrance(index: 1)

                    group("Recording") {
                        recordingRows
                    }
                    .murmurEntrance(index: 2)

                    group("Support") {
                        supportRows
                    }
                    .murmurEntrance(index: 3)
                    restoreStatus

                    group("About") {
                        aboutRows
                    }
                    .murmurEntrance(index: 4)

                    Text("Murmur \(version) · Everything stays on this iPhone")
                        .font(MurmurTheme.Fonts.caption)
                        .foregroundStyle(MurmurTheme.Colors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallScreen(controller: entitlements) { showPaywall = false }
        }
    }


    // MARK: - Rows shared by the iPhone list and the iPad panes

    @ViewBuilder
    private var transcriptionRows: some View {
                Menu {
                    ForEach(TranscriptionLanguage.all) { language in
                        Button {
                            settings.setLanguage(language.code)
                        } label: {
                            if language.code == settings.language {
                                Label(language.name, systemImage: "checkmark")
                            } else {
                                Text(language.name)
                            }
                        }
                    }
                } label: {
                    SettingsRow(systemImage: "globe", title: "Language", value: TranscriptionLanguage.name(for: settings.language))
                }
                divider
                NavigationLink {
                    ModelSettingsDestination(manager: deps.models)
                } label: {
                    SettingsRow(systemImage: "cpu", title: "Speech model", value: deps.models.selected.title)
                }
                divider
                NavigationLink {
                    DictionaryScreen()
                } label: {
                    SettingsRow(systemImage: "character.book.closed", title: "Custom dictionary",
                                value: "\(words.count) word\(words.count == 1 ? "" : "s")")
                }
    }

    @ViewBuilder
    private var recordingRows: some View {
                SettingsRow(systemImage: "trash", title: "Delete audio after transcribing",
                            isOn: Binding(get: { settings.deleteAudioAfterTranscribing },
                                          set: { settings.setDeleteAudioAfterTranscribing($0) }))
                divider
                SettingsRow(systemImage: "iphone.radiowaves.left.and.right", title: "Haptics",
                            isOn: Binding(get: { settings.hapticsEnabled },
                                          set: { settings.setHapticsEnabled($0) }))
    }

    @ViewBuilder
    private var supportRows: some View {
                Button {
                    Task { await entitlements.restore() }
                } label: {
                    SettingsRow(systemImage: "arrow.clockwise", title: "Restore purchases",
                                value: entitlements.state == .restoring ? "Restoring…" : nil)
                }
                .buttonStyle(.plain)
                .disabled(entitlements.isBusy)
    }

    @ViewBuilder
    private var aboutRows: some View {
                Link(destination: LegalLinks.privacy) {
                    SettingsRow(systemImage: "hand.raised", title: "Privacy Policy")
                }
                divider
                Link(destination: LegalLinks.terms) {
                    SettingsRow(systemImage: "doc.text", title: "Terms of Use")
                }
    }

    // MARK: - iPad: section list beside a detail pane (design/ipad/Settings.dc.html)

    private enum Pane: String, CaseIterable, Identifiable {
        case transcription, recording, dictionary, support, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .transcription: "Transcription"
            case .recording: "Recording"
            case .dictionary: "Custom dictionary"
            case .support: "Support"
            case .about: "About"
            }
        }
        var subtitle: String {
            switch self {
            case .transcription: "Language and the speech model that turns audio into text."
            case .recording: "What happens to your audio and how the app feels."
            case .dictionary: "Names and terms Murmur should spell your way."
            case .support: "Purchases on this Apple ID."
            case .about: "Privacy and terms."
            }
        }
        var symbol: String {
            switch self {
            case .transcription: "text.alignleft"
            case .recording: "mic"
            case .dictionary: "character.book.closed"
            case .support: "lifepreserver"
            case .about: "info.circle"
            }
        }
        var colorIndex: Int {
            switch self {
            case .transcription: 0
            case .recording: 3
            case .dictionary: 1
            case .support: 2
            case .about: 4
            }
        }
    }

    private var padLayout: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HeaderCircleButton(symbol: "xmark", label: "Close settings") { dismiss() }
                    Text("Settings")
                        .font(MurmurTheme.Fonts.title)
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.bottom, 12)
                proCard.padding(.bottom, 8)
                ForEach(Pane.allCases) { pane in
                    Button { self.pane = pane } label: {
                        HStack(spacing: 12) {
                            Image(systemName: pane.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MurmurTheme.Colors.background)
                                .frame(width: 28, height: 28)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(MurmurTheme.Colors.folder(pane.colorIndex)))
                            Text(pane.title)
                                .font(MurmurTheme.Fonts.body.weight(self.pane == pane ? .semibold : .regular))
                                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(self.pane == pane ? MurmurTheme.Colors.raised : Color.clear))
                    }
                    .buttonStyle(MurmurPressStyle())
                    .accessibilityAddTraits(self.pane == pane ? .isSelected : [])
                }
                Spacer(minLength: 0)
                Text("Murmur \(version) · Everything stays on this iPad")
                    .font(MurmurTheme.Fonts.caption)
                    .foregroundStyle(MurmurTheme.Colors.textTertiary)
                    .padding(.horizontal, 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 28)
            .frame(width: 320)
            .background(MurmurTheme.Colors.panel)
            .overlay(alignment: .trailing) {
                Rectangle().fill(MurmurTheme.Colors.border).frame(width: MurmurTheme.Metrics.borderWidth)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pane.title)
                            .font(MurmurTheme.Fonts.title)
                            .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        Text(pane.subtitle)
                            .font(MurmurTheme.Fonts.body)
                            .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    }
                    VStack(spacing: 0) {
                        switch pane {
                        case .transcription: transcriptionRows
                        case .recording: recordingRows
                        case .dictionary:
                            NavigationLink {
                                DictionaryScreen()
                            } label: {
                                SettingsRow(systemImage: "character.book.closed", title: "Custom dictionary",
                                            value: "\(words.count) word\(words.count == 1 ? "" : "s")")
                            }
                        case .support: supportRows
                        case .about: aboutRows
                        }
                    }
                    .frame(maxWidth: 620)
                    .murmurCard()
                    .clipShape(RoundedRectangle(cornerRadius: MurmurTheme.Metrics.cardRadius, style: .continuous))
                    if pane == .support { restoreStatus }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var divider: some View {
        Rectangle().fill(MurmurTheme.Colors.border).frame(height: MurmurTheme.Metrics.borderWidth).padding(.leading, 58)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).murmurSectionLabel().padding(.horizontal, 6)
            VStack(spacing: 0) { content() }
                .murmurCard()
                .clipShape(RoundedRectangle(cornerRadius: MurmurTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    private var proCard: some View {
        Button {
            if !entitlements.isPro { showPaywall = true }
        } label: {
            HStack(spacing: 14) {
                HStack(spacing: 2) {
                    ForEach(Array([18, 11, 5, 11, 18].enumerated()), id: \.offset) { _, height in
                        Capsule().fill(MurmurTheme.Colors.accent).frame(width: 3, height: CGFloat(height))
                    }
                }
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MurmurTheme.Colors.panel))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(MurmurTheme.Colors.border))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Murmur Pro")
                        .font(MurmurTheme.Fonts.headline)
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    Text(entitlements.activePlan.map { "\($0.title) · Active" } ?? "Free · first 2 minutes of each note")
                        .font(.footnote)
                        .foregroundStyle(MurmurTheme.Colors.accent)
                }
                Spacer(minLength: 0)
                if !entitlements.isPro {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MurmurTheme.Colors.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .murmurCard(selected: true)
        }
        .buttonStyle(MurmurPressStyle())
        .accessibilityHint(entitlements.isPro ? "" : "Opens the upgrade screen")
    }

    @ViewBuilder
    private var restoreStatus: some View {
        switch entitlements.state {
        case .message(let text):
            Text(text).font(.footnote).foregroundStyle(MurmurTheme.Colors.accent).padding(.horizontal, 6)
        case .failed(let text):
            Text(text).font(.footnote).foregroundStyle(MurmurTheme.Colors.record).padding(.horizontal, 6)
        default:
            EmptyView()
        }
    }
}

/// The model picker from first launch, reused inside Settings.
private struct ModelSettingsDestination: View {
    let manager: SpeechModelManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ModelDownloadScreen(manager: manager, onContinue: { dismiss() })
            .toolbar(.hidden, for: .navigationBar)
    }
}

/// Light tap feedback for main actions, unless the person turned haptics off.
@MainActor
enum Haptics {
    static func tap(_ settings: AppSettings) {
        guard settings.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
