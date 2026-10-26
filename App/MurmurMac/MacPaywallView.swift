import SwiftUI
import MurmurCore
import MurmurUI

/// Paywall window (design/mac/Paywall.dc.html): perks, three plan cards, one purchase for every device.
struct MacPaywallView: View {
    @Bindable var entitlements: EntitlementController
    let onClose: () -> Void

    private static let perks: [(String, String)] = [
        ("doc.text", "Full transcripts of any length"),
        ("sparkles", "Summaries and action items"),
        ("square.and.arrow.up", "Export to TXT, SRT, Markdown and audio"),
        ("tray.full", "Batch import of long files"),
        ("iphone.and.ipad", "One purchase for iPhone, iPad and Mac"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Murmur Pro").font(MurmurTheme.Mac.title).foregroundStyle(MurmurTheme.Colors.textPrimary)
                Text("Private transcription with no limits. Everything still runs on your device.")
                    .font(MurmurTheme.Mac.body).foregroundStyle(MurmurTheme.Colors.textSecondary)
                ForEach(Self.perks, id: \.1) { perk in
                    HStack(spacing: 10) {
                        Image(systemName: perk.0).frame(width: 22).foregroundStyle(MurmurTheme.Colors.accent)
                        Text(perk.1).font(MurmurTheme.Mac.body).foregroundStyle(MurmurTheme.Colors.textPrimary)
                    }
                }
                Spacer()
                Text("Free: the first 2 minutes of every note.")
                    .font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textTertiary)
            }
            .padding(28)
            .frame(width: 330, alignment: .topLeading)
            .background(MurmurTheme.Colors.panel)

            VStack(spacing: 12) {
                if entitlements.isPro {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 36)).foregroundStyle(MurmurTheme.Colors.accent)
                    Text("You have Murmur Pro").font(MurmurTheme.Mac.bodyBold).foregroundStyle(MurmurTheme.Colors.textPrimary)
                } else {
                    ForEach(Plan.allCases) { plan in
                        let offer = entitlements.offers.first { $0.plan == plan } ?? .placeholder(plan)
                        PlanCard(name: plan.title, price: offer.displayPrice, detail: offer.detail,
                                 badge: offer.badge, isSelected: entitlements.selected == plan) {
                            entitlements.selected = plan
                        }
                    }
                    PrimaryButton(entitlements.callToAction) { Task { await entitlements.purchase() } }
                        .disabled(entitlements.isBusy)
                    statusLine
                    HStack(spacing: 16) {
                        Button("Restore purchases") { Task { await entitlements.restore() } }
                        Link("Terms", destination: LegalLinks.terms)
                        Link("Privacy", destination: LegalLinks.privacy)
                    }
                    .buttonStyle(.plain).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textSecondary)
                    Text(LegalLinks.subscriptionNotice).font(.system(size: 10)).foregroundStyle(MurmurTheme.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
                Button(entitlements.isPro ? "Done" : "Not now", action: onClose)
                    .buttonStyle(.plain).font(MurmurTheme.Mac.body).foregroundStyle(MurmurTheme.Colors.textSecondary)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(28)
            .frame(width: 400)
        }
        .frame(height: 560)
        .background(MurmurTheme.Colors.background)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var statusLine: some View {
        switch entitlements.state {
        case .message(let text):
            Text(text).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.accent)
        case .failed(let text):
            Text(text).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.record)
        case .purchasing, .restoring:
            ProgressView().controlSize(.small)
        case .idle:
            EmptyView()
        }
    }
}

/// Model download sheet: choose the speech model, download with progress (onboarding step 4 and first record).
struct MacModelDownloadView: View {
    @Bindable var manager: SpeechModelManager
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Download the speech model").font(MurmurTheme.Mac.title).foregroundStyle(MurmurTheme.Colors.textPrimary)
            Text("Murmur transcribes on this Mac. The model downloads once; after that nothing needs the internet.")
                .font(MurmurTheme.Mac.body).foregroundStyle(MurmurTheme.Colors.textSecondary)
            ForEach(SpeechModel.choices) { model in
                Button { manager.select(model) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.title + (model.isRecommended ? " · Recommended" : ""))
                                .font(MurmurTheme.Mac.bodyBold).foregroundStyle(MurmurTheme.Colors.textPrimary)
                            Text("\(model.subtitle) · \(ByteText.format(model.approximateBytes))")
                                .font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textTertiary)
                        }
                        Spacer()
                        Image(systemName: manager.selected == model ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(manager.selected == model ? MurmurTheme.Colors.accent : MurmurTheme.Colors.textTertiary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(manager.selected == model ? MurmurTheme.Colors.selectedFill : MurmurTheme.Colors.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(manager.selected == model ? MurmurTheme.Colors.accent : MurmurTheme.Colors.border))
                }
                .buttonStyle(.plain)
                .disabled(manager.isDownloading)
            }
            switch manager.state {
            case .downloading(let fraction):
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: fraction).tint(MurmurTheme.Colors.accent)
                    Text("Downloading… \(Int(fraction * 100))%").font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textSecondary)
                }
            case .failed(let message):
                Text(message).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.record)
            case .ready:
                Label("Model ready", systemImage: "checkmark.circle.fill").foregroundStyle(MurmurTheme.Colors.accent)
                    .font(MurmurTheme.Mac.bodyBold)
            case .notDownloaded:
                EmptyView()
            }
            HStack {
                Spacer()
                if manager.isDownloading {
                    Button("Cancel") { manager.cancel() }
                } else if manager.isReady {
                    Button("Continue", action: onContinue).keyboardShortcut(.defaultAction)
                } else {
                    Button("Later", action: onContinue).keyboardShortcut(.cancelAction)
                    Button("Download") { manager.start() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(MurmurTheme.Colors.background)
        .preferredColorScheme(.dark)
    }
}
