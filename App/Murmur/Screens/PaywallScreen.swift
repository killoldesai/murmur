import SwiftUI
import MurmurCore
import MurmurUI

/// Murmur Pro: perks, three plans, Restore purchases. Matches design/iphone/Paywall.dc.html.
struct PaywallScreen: View {
    let controller: EntitlementController
    let onClose: () -> Void

    private let perks: [(String, Int)] = [
        ("Unlimited length", 0),
        ("Speaker labels", 1),
        ("AI summaries", 2),
        ("Custom dictionary", 3)
    ]
    private let perkColors: [Color] = [
        MurmurTheme.Colors.folder(0), MurmurTheme.Colors.folder(1),
        MurmurTheme.Colors.folder(2), MurmurTheme.Colors.folder(4)
    ]

    var body: some View {
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.footnote.weight(.heavy))
                                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                                .frame(width: MurmurTheme.Metrics.minTapTarget, height: MurmurTheme.Metrics.minTapTarget)
                                .background(Circle().fill(MurmurTheme.Colors.surface))
                                .overlay(Circle().strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth))
                        }
                        .buttonStyle(MurmurPressStyle())
                        .accessibilityLabel("Close")
                    }
                    .padding(.top, 8)

                    header.padding(.top, 4).murmurEntrance(index: 0)
                    perksCard.padding(.top, 22).murmurEntrance(index: 1)
                    plans.padding(.top, 20).murmurEntrance(index: 2)
                }
                .padding(.horizontal, MurmurTheme.Metrics.screenPadding)
                .padding(.bottom, 12)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .preferredColorScheme(.dark)
        .onChange(of: controller.isPro) { _, isPro in
            if isPro { onClose() }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            AppIconMark()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                (Text("Murmur ").foregroundStyle(MurmurTheme.Colors.textPrimary)
                    + Text("Pro").foregroundStyle(MurmurTheme.Colors.accent))
                    .font(MurmurTheme.Fonts.title)
                    .accessibilityAddTraits(.isHeader)
                Text("Unlimited, private transcription. No cloud, ever.")
                    .font(MurmurTheme.Fonts.body)
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                Text("Free: the first 2 minutes of every note.")
                    .font(.footnote)
                    .foregroundStyle(MurmurTheme.Colors.textTertiary)
            }
        }
    }

    private var perksCard: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], alignment: .leading, spacing: 14) {
            ForEach(perks, id: \.0) { perk in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(MurmurTheme.Colors.background)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(perkColors[perk.1]))
                        .accessibilityHidden(true)
                    Text(perk.0)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .murmurCard()
    }

    private var plans: some View {
        VStack(spacing: 10) {
            ForEach(controller.offers) { offer in
                PlanCard(
                    name: offer.plan.title,
                    price: offer.displayPrice,
                    detail: offer.detail,
                    badge: offer.badge,
                    isSelected: controller.selected == offer.plan
                ) { controller.selected = offer.plan }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose a plan")
    }

    private var footer: some View {
        VStack(spacing: 6) {
            statusLine
            PrimaryButton(controller.state == .purchasing ? "Working…" : controller.callToAction, action: {
                Task { await controller.purchase() }
            })
            .disabled(controller.isBusy)
            Text(LegalLinks.subscriptionNotice)
                .font(.caption2)
                .foregroundStyle(MurmurTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    Task { await controller.restore() }
                } label: {
                    Text(controller.state == .restoring ? "Restoring…" : "Restore purchases")
                        .font(.footnote)
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                        .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
                        .padding(.horizontal, 8)
                }
                .disabled(controller.isBusy)
                Link("Terms", destination: LegalLinks.terms)
                    .font(.footnote)
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
                    .padding(.horizontal, 8)
                Link("Privacy", destination: LegalLinks.privacy)
                    .font(.footnote)
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, MurmurTheme.Metrics.screenPadding)
        .padding(.top, 10)
        .background(MurmurTheme.Colors.background)
        .overlay(alignment: .top) {
            Rectangle().fill(MurmurTheme.Colors.border).frame(height: MurmurTheme.Metrics.borderWidth)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch controller.state {
        case .message(let text):
            Text(text)
                .font(.footnote)
                .foregroundStyle(MurmurTheme.Colors.accent)
                .multilineTextAlignment(.center)
        case .failed(let text):
            Text(text)
                .font(.footnote)
                .foregroundStyle(MurmurTheme.Colors.record)
                .multilineTextAlignment(.center)
        default:
            EmptyView()
        }
    }
}

/// The app icon's five bars on a dark tile.
private struct AppIconMark: View {
    private let heights: [CGFloat] = [0.46, 0.27, 0.10, 0.27, 0.46]

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                    .fill(MurmurTheme.Colors.panel)
                RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                    .strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth)
                HStack(spacing: side * 0.054) {
                    ForEach(heights.indices, id: \.self) { index in
                        Capsule()
                            .fill(MurmurTheme.Colors.accent)
                            .frame(width: side * 0.075, height: side * heights[index])
                    }
                }
            }
        }
    }
}
