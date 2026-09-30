import SwiftUI

private struct RecipeReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

public extension EnvironmentValues {
    /// A nil override follows the system preference. UI fixtures can supply
    /// either value without changing macOS accessibility settings.
    var recipeReduceMotionOverride: Bool? {
        get { self[RecipeReduceMotionOverrideKey.self] }
        set { self[RecipeReduceMotionOverrideKey.self] = newValue }
    }

    var recipeReduceMotion: Bool {
        recipeReduceMotionOverride ?? accessibilityReduceMotion
    }
}

/// Shared by recipe interactions and the root scene's tab navigation.
/// Reduce Motion removes spatial effects; the standard animations are kept
/// unchanged when the accessibility preference is off.
public struct MotionPolicy: Sendable {
    public let reduceMotion: Bool

    public init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }

    public func animation(_ standard: Animation) -> Animation? {
        reduceMotion ? nil : standard
    }

    public func transition(_ standard: AnyTransition) -> AnyTransition {
        reduceMotion ? .identity : standard
    }

    /// Also removes static hover/press enlargement, rather than making it jump.
    public func scale(_ standard: CGFloat) -> CGFloat {
        reduceMotion ? 1 : standard
    }

    public func apply(to transaction: inout Transaction) {
        guard reduceMotion else { return }
        transaction.animation = nil
        transaction.disablesAnimations = true
    }
}

private struct ReducedMotionModifier: ViewModifier {
    @Environment(\.recipeReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .transaction { transaction in
                MotionPolicy(reduceMotion: reduceMotion).apply(to: &transaction)
            }
            .symbolEffectsRemoved(reduceMotion)
    }
}

public extension View {
    /// Stops inherited transactions and symbol effects from reintroducing
    /// animation inside a view that honors Reduce Motion.
    func respectingReducedMotion() -> some View {
        modifier(ReducedMotionModifier())
    }
}
