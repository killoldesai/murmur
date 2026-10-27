import SwiftUI
import MurmurCore

/// Slide a row left to reveal a Delete button. The button only asks for deletion: the caller
/// shows its own confirmation. VoiceOver gets a "Delete" action instead of the gesture.
public struct SwipeToDelete<Content: View>: View {
    private let onDelete: () -> Void
    private let content: Content
    @State private var revealed: Bool
    @State private var drag: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let buttonWidth: Double = 84

    public init(startsRevealed: Bool = false, onDelete: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onDelete = onDelete
        self.content = content()
        _revealed = State(initialValue: startsRevealed)
    }

    private var offset: Double {
        SwipeReveal.offset(revealed: revealed, translation: drag, buttonWidth: buttonWidth)
    }

    public var body: some View {
        content
            .overlay {
                // While the button is showing, a tap on the row closes it instead of opening the note.
                if revealed {
                    Color.clear.contentShape(Rectangle()).onTapGesture { close() }
                }
            }
            .offset(x: offset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 14)
                    .onChanged { value in
                        // Only a mostly horizontal drag moves the row, so scrolling still works.
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        drag = value.translation.width
                    }
                    .onEnded { value in
                        let stay = SwipeReveal.settle(
                            revealed: revealed,
                            predictedEnd: value.predictedEndTranslation.width,
                            buttonWidth: buttonWidth
                        )
                        animate { revealed = stay; drag = 0 }
                    }
            )
            // The button sits behind the row at the trailing edge and takes the row's height.
            .background(alignment: .trailing) {
                Button(action: delete) {
                    VStack(spacing: 4) {
                        Image(systemName: "trash").font(.headline)
                        Text("Delete").font(MurmurTheme.Fonts.caption.weight(.semibold))
                    }
                    .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    .frame(width: buttonWidth)
                    .frame(maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: MurmurTheme.Metrics.cardRadius, style: .continuous)
                            .fill(MurmurTheme.Colors.record)
                    )
                }
                .buttonStyle(MurmurPressStyle())
                .opacity(offset < 0 ? 1 : 0)
                .allowsHitTesting(revealed)
                .accessibilityHidden(true)
            }
            .accessibilityAction(named: "Delete", delete)
    }

    private func delete() {
        close()
        onDelete()
    }

    private func close() {
        animate { revealed = false; drag = 0 }
    }

    private func animate(_ change: () -> Void) {
        if reduceMotion {
            change()
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85), change)
        }
    }
}
