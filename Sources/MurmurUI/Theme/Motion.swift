import SwiftUI

/// Motion constants from the spec. Every effect here is disabled under Reduce Motion.
public enum MurmurMotion {
    /// Screen-entry spring: response 0.5, damping 0.85.
    public static let spring = Animation.spring(response: 0.5, dampingFraction: 0.85)
    public static let entryOffset: CGFloat = 16
    public static let pressScale: CGFloat = 0.96
    /// Per-item stagger, within the spec's 50-80 ms range.
    public static let staggerStep: Double = 0.06

    public static func staggerDelay(index: Int) -> Double {
        Double(max(0, index)) * staggerStep
    }
}

private struct EntranceModifier: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: (shown || reduceMotion) ? 0 : MurmurMotion.entryOffset)
            .onAppear {
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(MurmurMotion.spring.delay(MurmurMotion.staggerDelay(index: index))) {
                        shown = true
                    }
                }
            }
    }
}

public extension View {
    /// Rises 16 pt and fades in on appear, staggered by `index`.
    func murmurEntrance(index: Int = 0) -> some View {
        modifier(EntranceModifier(index: index))
    }
}

/// Press feedback: scales to 0.96. Use on every tappable button and card.
public struct MurmurPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? MurmurMotion.pressScale : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
