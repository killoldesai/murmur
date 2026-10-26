import SwiftUI
import MurmurCore
import MurmurUI

/// Three feature pages, then the microphone explanation. Matches design/iphone/Onboard1-3 and Mic.
struct OnboardingScreen: View {
    @State private var controller: OnboardingController
    @State private var asking = false
    let requestMicrophone: () async -> Void
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(startAt: Int = 0, requestMicrophone: @escaping () async -> Void, onFinish: @escaping () -> Void) {
        _controller = State(initialValue: OnboardingController(startAt: startAt))
        self.requestMicrophone = requestMicrophone
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
            Group {
                if let page = controller.page {
                    featurePage(page)
                } else {
                    microphonePage
                }
            }
            .id(controller.index)
            .transition(.opacity)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: controller.index)
        .preferredColorScheme(.dark)
    }

    // MARK: - Feature pages

    private func featurePage(_ page: OnboardingPage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { controller.skip() }
                    .font(MurmurTheme.Fonts.body)
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
            }
            Spacer(minLength: 0)
            illustration(symbol: page.symbol)
                .frame(maxWidth: .infinity)
                .murmurEntrance(index: 0)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                Text(page.title)
                    .font(MurmurTheme.Fonts.largeTitle)
                    .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(page.body)
                    .font(MurmurTheme.Fonts.body)
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .murmurEntrance(index: 1)
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<controller.pageCount, id: \.self) { dot in
                        Capsule()
                            .fill(dot == controller.index ? MurmurTheme.Colors.accent : MurmurTheme.Colors.raised)
                            .frame(width: dot == controller.index ? 22 : 8, height: 8)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Page \(controller.index + 1) of \(controller.pageCount)")
                Spacer()
                Button { controller.next() } label: {
                    HStack(spacing: 8) {
                        Text("Continue").font(MurmurTheme.Fonts.headline)
                        Image(systemName: "arrow.right").font(.body.weight(.bold))
                    }
                    .foregroundStyle(MurmurTheme.Colors.onAccent)
                    .padding(.horizontal, 28)
                    .frame(height: MurmurTheme.Metrics.buttonHeight)
                    .background(RoundedRectangle(cornerRadius: MurmurTheme.Metrics.buttonRadius, style: .continuous).fill(MurmurTheme.Colors.accent))
                }
                .buttonStyle(MurmurPressStyle())
            }
            .padding(.top, 28)
            .murmurEntrance(index: 2)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    private func illustration(symbol: String) -> some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(Array([30, 20, 8, 20, 30].enumerated()), id: \.offset) { _, height in
                        Capsule().fill(MurmurTheme.Colors.accent).frame(width: 5, height: CGFloat(height))
                    }
                }
                .frame(height: 40)
                ForEach([1.0, 0.86, 0.94, 0.6, 0.9], id: \.self) { width in
                    GeometryReader { proxy in
                        Capsule().fill(MurmurTheme.Colors.raised)
                            .frame(width: proxy.size.width * width, height: 10)
                    }
                    .frame(height: 10)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 36)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(width: 210, height: 330)
            .background(RoundedRectangle(cornerRadius: 40, style: .continuous).fill(MurmurTheme.Colors.surface))
            .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous).strokeBorder(MurmurTheme.Colors.border))

            Image(systemName: symbol)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(MurmurTheme.Colors.onAccent)
                .frame(width: 76, height: 76)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(MurmurTheme.Colors.accent))
                .offset(x: 26, y: -50)
        }
        .padding(.trailing, 26)
        .accessibilityHidden(true)
    }

    // MARK: - Microphone step

    private var microphonePage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 32) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(MurmurTheme.Colors.onAccent)
                    .frame(width: 132, height: 132)
                    .background(Circle().fill(MurmurTheme.Colors.accent))
                    .accessibilityHidden(true)
                    .murmurEntrance(index: 0)
                VStack(spacing: 10) {
                    Text("Allow the microphone")
                        .font(MurmurTheme.Fonts.title)
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Murmur needs your mic to record. Audio is processed on this iPhone and never sent anywhere.")
                        .font(MurmurTheme.Fonts.body)
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .murmurEntrance(index: 1)
                VStack(spacing: 0) {
                    assurance("shield.lefthalf.filled", "Only records when you tap record")
                    Rectangle().fill(MurmurTheme.Colors.border).frame(height: MurmurTheme.Metrics.borderWidth)
                    assurance("wifi.slash", "No network access needed to transcribe")
                }
                .murmurCard()
                .murmurEntrance(index: 2)
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                PrimaryButton(asking ? "Waiting…" : "Allow microphone") {
                    guard !asking else { return }
                    asking = true
                    Task { @MainActor in
                        await requestMicrophone()
                        asking = false
                        onFinish()
                    }
                }
                Button("Not now", action: onFinish)
                    .font(MurmurTheme.Fonts.body)
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
            }
            .murmurEntrance(index: 3)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    private func assurance(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(MurmurTheme.Colors.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}
