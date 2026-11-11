import SwiftUI

/// Paywall plan option with a radio dot and an optional badge.
public struct PlanCard: View {
    let name: String
    let price: String
    let detail: String
    let unit: String?
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    public init(
        name: String,
        price: String,
        unit: String? = nil,
        detail: String,
        badge: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.name = name
        self.price = price
        self.unit = unit
        self.detail = detail
        self.badge = badge
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? MurmurTheme.Colors.accent : MurmurTheme.Colors.textTertiary, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    Circle()
                        .fill(MurmurTheme.Colors.accent)
                        .frame(width: 12, height: 12)
                        .scaleEffect(isSelected ? 1 : 0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(name)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .font(MurmurTheme.Fonts.headline)
                            .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.heavy))
                                .tracking(0.6)
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundStyle(MurmurTheme.Colors.onAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(MurmurTheme.Colors.accent))
                        }
                    }
                    Text(detail)
                        .font(MurmurTheme.Fonts.caption)
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                // The billed amount is the largest, boldest text on the card (App Review 3.1.2(c)).
                VStack(alignment: .trailing, spacing: 1) {
                    Text(price)
                        .font(.title3.weight(.heavy).monospacedDigit())
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    if let unit {
                        Text(unit)
                            .font(MurmurTheme.Fonts.caption)
                            .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    }
                }
                .fixedSize()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .murmurCard(selected: isSelected)
        }
        .buttonStyle(MurmurPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
