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
    @State private var showPaywall = false

    private var settings: AppSettings { deps.settings }
    private var entitlements: EntitlementController { deps.entitlements }

    var body: some View {
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
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
                    .murmurEntrance(index: 1)

                    group("Recording") {
                        SettingsRow(systemImage: "trash", title: "Delete audio after transcribing",
                                    isOn: Binding(get: { settings.deleteAudioAfterTranscribing },
                                                  set: { settings.setDeleteAudioAfterTranscribing($0) }))
                        divider
                        SettingsRow(systemImage: "iphone.radiowaves.left.and.right", title: "Haptics",
                                    isOn: Binding(get: { settings.hapticsEnabled },
                                                  set: { settings.setHapticsEnabled($0) }))
                    }
                    .murmurEntrance(index: 2)

                    group("Support") {
                        Button {
                            Task { await entitlements.restore() }
                        } label: {
                            SettingsRow(systemImage: "arrow.clockwise", title: "Restore purchases",
                                        value: entitlements.state == .restoring ? "Restoring…" : nil)
                        }
                        .buttonStyle(.plain)
                        .disabled(entitlements.isBusy)
                    }
                    .murmurEntrance(index: 3)
                    restoreStatus

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
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallScreen(controller: entitlements) { showPaywall = false }
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
