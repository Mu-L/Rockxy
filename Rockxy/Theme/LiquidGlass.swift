import AppKit
import SwiftUI

// MARK: - LiquidGlassRenderingPolicy

/// Pure, testable policy that decides how a Rockxy glass surface should render.
///
/// The resolver deliberately avoids `#available` checks and SwiftUI environment reads so every
/// combination can be unit-tested. Callers pass the runtime facts (macOS 26 availability plus the
/// two accessibility preferences) and the resolver returns a single deterministic decision.
enum LiquidGlassRenderingPolicy {
    /// The rendering treatment selected for a glass surface.
    enum Decision: Equatable {
        /// Native macOS 26 Liquid Glass — only when the API exists and no accessibility preference
        /// forces an opaque surface.
        case liquidGlass
        /// System material fallback on older supported systems when accessibility does not require
        /// opacity.
        case systemMaterial
        /// Deterministic opaque system color when Reduce Transparency or Increase Contrast is on.
        case opaqueColor
    }

    /// Resolves the rendering decision from the current runtime facts.
    ///
    /// Accessibility wins first: if either Reduce Transparency or Increase Contrast is on, the
    /// surface is opaque regardless of macOS version. Otherwise Liquid Glass is used when available,
    /// falling back to system material on older systems.
    static func resolve(
        liquidGlassAvailable: Bool,
        reduceTransparency: Bool,
        increaseContrast: Bool
    )
        -> Decision
    {
        if reduceTransparency || increaseContrast {
            return .opaqueColor
        }
        return liquidGlassAvailable ? .liquidGlass : .systemMaterial
    }
}

// MARK: - LiquidGlassAppearanceIdentity

/// Identity for native glass instances whose sampled tone is retained by AppKit across an
/// in-place appearance transition. Changing any appearance input deliberately recreates the
/// native effect instead of letting a Light material survive inside a Dark hierarchy (or vice
/// versa).
struct LiquidGlassAppearanceIdentity: Hashable {
    let isDark: Bool
    let reduceTransparency: Bool
    let increaseContrast: Bool
}

// MARK: - RockxyGlassEffectGroup

/// Availability-safe grouping for nearby Liquid Glass controls.
///
/// macOS 26 shares one sampling region across the group so adjacent glass controls render
/// consistently. Earlier releases keep the same layout and use each control's material fallback.
struct RockxyGlassEffectGroup<Content: View>: View {
    // MARK: Lifecycle

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    // MARK: Internal

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
            .id(appearanceIdentity)
        } else {
            content
        }
    }

    // MARK: Private

    private let spacing: CGFloat?
    private let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var appearanceIdentity: LiquidGlassAppearanceIdentity {
        LiquidGlassAppearanceIdentity(
            isDark: colorScheme == .dark,
            reduceTransparency: reduceTransparency,
            increaseContrast: colorSchemeContrast == .increased
        )
    }
}

// MARK: - Liquid Glass compatibility

extension View {
    /// Applies Liquid Glass to a custom functional surface while preserving Rockxy's macOS 14
    /// deployment target. The rendering treatment is chosen by ``LiquidGlassRenderingPolicy`` from
    /// the live SwiftUI accessibility environment: Liquid Glass on macOS 26 when no accessibility
    /// preference forces opacity, system material on older systems, and a deterministic opaque
    /// system color whenever Reduce Transparency or Increase Contrast is on.
    func rockxyGlassEffect(
        tint: Color? = nil,
        interactive: Bool = false,
        in shape: some InsettableShape
    )
        -> some View
    {
        modifier(RockxyGlassEffectModifier(tint: tint, interactive: interactive, shape: shape))
    }

    /// Uses the native Liquid Glass button family on macOS 26 and standard bordered controls on
    /// older supported systems. Callers retain their existing control size and accessibility.
    func rockxyGlassButtonStyle(prominent: Bool = false) -> some View {
        modifier(RockxyGlassButtonStyleModifier(prominent: prominent))
    }

    /// Applies Rockxy's readable semantic-chip treatment. Chips intentionally remain a tinted,
    /// high-contrast status surface rather than becoming tiny nested glass islands. Active and
    /// hover states use a tint wash plus stroke, so accent color never replaces the label.
    func rockxyChipStyle(
        tint: Color = .accentColor,
        isActive: Bool = false,
        isHovered: Bool = false,
        isEnabled: Bool = true
    )
        -> some View
    {
        modifier(RockxyChipModifier(
            tint: tint,
            isActive: isActive,
            isHovered: isHovered,
            isEnabled: isEnabled
        ))
    }

    /// Gives a compact header or footer the native macOS floating functional material. On macOS 26
    /// this is real Liquid Glass, so shared feature-window chrome gains refraction and specular
    /// response instead of remaining a flat `.bar` blur.
    /// Accessibility preferences and earlier macOS releases retain the deterministic fallbacks
    /// used by every other Rockxy glass surface.
    func rockxyFunctionalBar() -> some View {
        modifier(RockxyFunctionalBarModifier())
    }
}

// MARK: - RockxyFunctionalBarModifier

/// Turns the dozens of compact feature-window bars into one coherent floating functional layer.
/// The small outer inset lets surrounding content remain visible beneath the glass. Native glass
/// owns its optical edge and elevation; adding a painted stroke or shadow here would flatten the
/// adaptive highlight that distinguishes Liquid Glass from a translucent rounded rectangle.
private struct RockxyFunctionalBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: Theme.Glass.functionalBarCornerRadius,
            style: .continuous
        )

        content
            .rockxyGlassRendering(
                LiquidGlassRenderingPolicy.resolve(
                    liquidGlassAvailable: Self.isLiquidGlassAvailable,
                    reduceTransparency: reduceTransparency,
                    increaseContrast: colorSchemeContrast == .increased
                ),
                tint: nil,
                interactive: false,
                in: shape
            )
            .id(appearanceIdentity)
            .padding(.horizontal, Theme.Glass.functionalBarHorizontalInset)
            .padding(.vertical, Theme.Glass.functionalBarVerticalInset)
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var appearanceIdentity: LiquidGlassAppearanceIdentity {
        LiquidGlassAppearanceIdentity(
            isDark: colorScheme == .dark,
            reduceTransparency: reduceTransparency,
            increaseContrast: colorSchemeContrast == .increased
        )
    }

    private static var isLiquidGlassAvailable: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }
}

// MARK: - RockxyGlassButtonStyleModifier

/// Native glass controls can retain their previous sampled tone through an in-place app theme
/// change. Keying the styled control to the live appearance inputs keeps buttons aligned with the
/// surrounding glass surface without changing their state or accessibility contract otherwise.
private struct RockxyGlassButtonStyleModifier: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content
                    .buttonStyle(.glassProminent)
                    .id(appearanceIdentity)
            } else {
                content
                    .buttonStyle(.glass)
                    .id(appearanceIdentity)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var appearanceIdentity: LiquidGlassAppearanceIdentity {
        LiquidGlassAppearanceIdentity(
            isDark: colorScheme == .dark,
            reduceTransparency: reduceTransparency,
            increaseContrast: colorSchemeContrast == .increased
        )
    }
}

// MARK: - RockxyChipModifier

private struct RockxyChipModifier: ViewModifier {
    let tint: Color
    let isActive: Bool
    let isHovered: Bool
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .foregroundStyle(foregroundColor)
            .background(fillColor, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: colorSchemeContrast == .increased ? 1 : 0.75)
                    .allowsHitTesting(false)
            }
            .contentShape(Capsule(style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
    }

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var foregroundColor: Color {
        isActive ? tint : .primary
    }

    private var fillColor: Color {
        if isActive {
            return tint.opacity(
                isHovered ? Theme.Glass.semanticHoverFillOpacity : Theme.Glass.semanticFillOpacity
            )
        }
        return Color.primary.opacity(isHovered ? Theme.Glass.hoverFillOpacity : Theme.Glass.neutralFillOpacity)
    }

    private var strokeColor: Color {
        if isActive {
            return tint.opacity(
                isHovered ? Theme.Glass.semanticHoverStrokeOpacity : Theme.Glass.semanticStrokeOpacity
            )
        }
        return Color.primary.opacity(
            colorSchemeContrast == .increased
                ? Theme.Glass.semanticStrokeOpacity
                : Theme.Glass.neutralStrokeOpacity
        )
    }
}

// MARK: - RockxyGlassEffectModifier

/// Reads the SwiftUI accessibility environment, resolves the rendering decision via
/// ``LiquidGlassRenderingPolicy``, and applies the matching surface treatment.
private struct RockxyGlassEffectModifier<S: InsettableShape>: ViewModifier {
    // MARK: Internal

    let tint: Color?
    let interactive: Bool
    let shape: S

    func body(content: Content) -> some View {
        content.rockxyGlassRendering(
            LiquidGlassRenderingPolicy.resolve(
                liquidGlassAvailable: Self.isLiquidGlassAvailable,
                reduceTransparency: reduceTransparency,
                increaseContrast: colorSchemeContrast == .increased
            ),
            tint: tint,
            interactive: interactive,
            in: shape
        )
        .id(appearanceIdentity)
    }

    // MARK: Private

    private static var isLiquidGlassAvailable: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var appearanceIdentity: LiquidGlassAppearanceIdentity {
        LiquidGlassAppearanceIdentity(
            isDark: colorScheme == .dark,
            reduceTransparency: reduceTransparency,
            increaseContrast: colorSchemeContrast == .increased
        )
    }
}

// MARK: - Rendering treatments

private extension View {
    @ViewBuilder
    func rockxyGlassRendering(
        _ decision: LiquidGlassRenderingPolicy.Decision,
        tint: Color?,
        interactive: Bool,
        in shape: some InsettableShape
    )
        -> some View
    {
        switch decision {
        case .liquidGlass:
            if #available(macOS 26.0, *) {
                glassEffect(
                    Glass.regular
                        .tint(tint)
                        .interactive(interactive),
                    in: shape
                )
            } else {
                rockxyMaterialSurface(tint: tint, in: shape)
            }
        case .systemMaterial:
            rockxyMaterialSurface(tint: tint, in: shape)
        case .opaqueColor:
            rockxyOpaqueSurface(tint: tint, in: shape)
        }
    }

    /// System material fallback — the closest system-managed translucency for older systems.
    @ViewBuilder
    func rockxyMaterialSurface(tint: Color?, in shape: some InsettableShape) -> some View {
        if let tint {
            background(tint.opacity(Theme.Glass.fallbackTintOpacity), in: shape)
                .overlay {
                    shape.strokeBorder(tint.opacity(Theme.Glass.fallbackStrokeOpacity), lineWidth: 0.5)
                }
        } else {
            background(.regularMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(Theme.Glass.neutralStrokeOpacity), lineWidth: 0.5)
                }
        }
    }

    /// Deterministic opaque fallback for Reduce Transparency / Increase Contrast. The opaque system
    /// window color forms the base so the surface never reads as translucent, while the same tint
    /// wash and stroke keep tint behavior and shape identical to the material path.
    func rockxyOpaqueSurface(tint: Color?, in shape: some InsettableShape) -> some View {
        background(Color(nsColor: .windowBackgroundColor), in: shape)
            .overlay {
                if let tint {
                    shape.fill(tint.opacity(Theme.Glass.fallbackTintOpacity))
                }
            }
            .overlay {
                shape.strokeBorder(
                    tint?.opacity(Theme.Glass.fallbackStrokeOpacity)
                        ?? Color.primary.opacity(Theme.Glass.neutralStrokeOpacity),
                    lineWidth: 0.5
                )
            }
    }
}
