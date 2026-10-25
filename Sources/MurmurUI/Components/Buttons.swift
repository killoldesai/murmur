import SwiftUI

/// Full-width accent button. 56 pt tall, 18 pt radius.
public struct PrimaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.headline)
                }
                Text(title).font(MurmurTheme.Fonts.headline)
            }
            .foregroundStyle(MurmurTheme.Colors.onAccent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: MurmurTheme.Metrics.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: MurmurTheme.Metrics.buttonRadius, style: .continuous)
                    .fill(MurmurTheme.Colors.accent)
            )
        }
        .buttonStyle(MurmurPressStyle())
    }
}

/// Full-width raised button with a 1 pt border.
public struct SecondaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.headline)
                }
                Text(title).font(MurmurTheme.Fonts.headline)
            }
            .foregroundStyle(MurmurTheme.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: MurmurTheme.Metrics.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: MurmurTheme.Metrics.buttonRadius, style: .continuous)
                    .fill(MurmurTheme.Colors.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MurmurTheme.Metrics.buttonRadius, style: .continuous)
                    .strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth)
            )
        }
        .buttonStyle(MurmurPressStyle())
    }
}

/// Fully rounded filter chip. Selected: selectedFill with an accent border.
public struct Chip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(MurmurTheme.Fonts.body.weight(.semibold))
                .foregroundStyle(isSelected ? MurmurTheme.Colors.accent : MurmurTheme.Colors.textSecondary)
                .padding(.horizontal, 16)
                .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
                .background(Capsule().fill(isSelected ? MurmurTheme.Colors.selectedFill : MurmurTheme.Colors.surface))
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? MurmurTheme.Colors.accent : MurmurTheme.Colors.border,
                        lineWidth: isSelected ? MurmurTheme.Metrics.selectedBorderWidth : MurmurTheme.Metrics.borderWidth
                    )
                )
        }
        .buttonStyle(MurmurPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
