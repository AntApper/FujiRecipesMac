import SwiftUI

// MARK: - 2026 Obsidian & Satin Glass Design System
//
// Inspired by precision Fujifilm camera craftsmanship (machined dials, titanium
// & obsidian satin textures, amber/fuji-red precision readouts, and ultra-fluid
// macOS 15/16 spatial glass materials).

public enum Theme {
    // Primary Colors
    public static let obsidianBlack = Color(red: 0.05, green: 0.055, blue: 0.065)
    public static let deepCharcoal  = Color(red: 0.09, green: 0.095, blue: 0.11)
    public static let satinSurface  = Color(red: 0.13, green: 0.135, blue: 0.155)
    
    // Brand & Fuji Precision Accents
    public static let fujiAmber     = Color(red: 1.00, green: 0.65, blue: 0.20) // Classic dial engraving amber
    public static let fujiRed       = Color(red: 0.94, green: 0.24, blue: 0.26) // Shutter release dot
    public static let titaniumMist  = Color(red: 0.88, green: 0.90, blue: 0.94) // Machined silver
    public static let cyanAccent    = Color(red: 0.24, green: 0.78, blue: 0.98) // Digital display cyan
    public static let emeraldGreen  = Color(red: 0.20, green: 0.84, blue: 0.56) // Success & link ready
    public static let violetAccent  = Color(red: 0.68, green: 0.44, blue: 0.98) // Special feature
    public static let warmGold      = Color(red: 0.96, green: 0.78, blue: 0.38) // Star / Favorite gold
    
    // Glass Surface Tokens
    public static let glassPanelBg       = Color.white.opacity(0.04)
    public static let glassElevatedBg    = Color.white.opacity(0.07)
    public static let glassInteractiveBg = Color.white.opacity(0.06)
    public static let glassHoverBg       = Color.white.opacity(0.10)
    public static let glassActiveBg      = Color.white.opacity(0.14)
    
    // Specular Borders & Strokes
    public static let specularBorder     = Color.white.opacity(0.14)
    public static let specularGlowBorder = Color.white.opacity(0.24)
    public static let subtleBorder       = Color.white.opacity(0.08)
    
    // Text Hierarchy
    public static let textPrimary        = Color.white
    public static let textSecondary      = Color.white.opacity(0.72)
    public static let textTertiary       = Color.white.opacity(0.46)
    public static let textMuted          = Color.white.opacity(0.28)
    
    // Film Simulation Thematic Tints
    public static func filmSimColor(for simName: String) -> Color {
        let lower = simName.lowercased()
        if lower.contains("reala") || lower.contains("provia") {
            return Color(red: 0.28, green: 0.65, blue: 0.98)
        } else if lower.contains("velvia") {
            return Color(red: 0.98, green: 0.32, blue: 0.45)
        } else if lower.contains("astia") {
            return Color(red: 0.98, green: 0.58, blue: 0.62)
        } else if lower.contains("classic chrome") {
            return Color(red: 0.48, green: 0.76, blue: 0.65)
        } else if lower.contains("classic neg") || lower.contains("negative") {
            return Color(red: 0.88, green: 0.54, blue: 0.38)
        } else if lower.contains("nostalgic") {
            return Color(red: 0.92, green: 0.70, blue: 0.42)
        } else if lower.contains("acros") || lower.contains("mono") || lower.contains("black") {
            return Color(red: 0.85, green: 0.87, blue: 0.92)
        } else if lower.contains("eterna") {
            return Color(red: 0.24, green: 0.74, blue: 0.70)
        } else if lower.contains("sepia") {
            return Color(red: 0.82, green: 0.62, blue: 0.40)
        }
        return fujiAmber
    }
}

public enum Glass {
    public static let cardRadius: CGFloat = 16
    public static let panelRadius: CGFloat = 20
    public static let buttonRadius: CGFloat = 22
    public static let pillRadius: CGFloat = 12
    public static let badgeRadius: CGFloat = 8

    public static let cardPadding: CGFloat = 16
    public static let panelPadding: CGFloat = 20

    public static let shadowColor = Color.black.opacity(0.36)
    public static let shadowRadius: CGFloat = 16
    public static let shadowYOffset: CGFloat = 6

    public static let strokeColor = Color.white.opacity(0.12)
    public static let strokeWidth: CGFloat = 0.8

    public static let panelTint = Color.white.opacity(0.04)
    public static let highlight = Color.white.opacity(0.10)

    public static let captionSecondary = Color.white.opacity(0.68)
    public static let bodyPrimary: Color = .white
}

// MARK: - Window Backdrop with Dynamic Ambient Lighting

public struct GlassWindowBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ambientPhase: Bool = false
    
    public init() {}

    public var body: some View {
        ZStack {
            // Deep obsidian foundation
            Theme.obsidianBlack.ignoresSafeArea()
            
            // Radial ambient atmospheric glows (Fuji warmth & cool titanium)
            GeometryReader { geo in
                ZStack {
                    // Warm amber top-left glow (analog studio lamp)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Theme.fujiAmber.opacity(0.12),
                                    Theme.fujiAmber.opacity(0.02),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: 360
                            )
                        )
                        .frame(width: 500, height: 500)
                        .position(x: geo.size.width * 0.15, y: geo.size.height * 0.1)
                        .blur(radius: 50)
                        .offset(x: ambientPhase ? 15 : -15, y: ambientPhase ? -10 : 10)
                    
                    // Cool sapphire / cyan bottom-right glow (digital sensor readout)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Theme.cyanAccent.opacity(0.08),
                                    Theme.cyanAccent.opacity(0.01),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: 400
                            )
                        )
                        .frame(width: 600, height: 600)
                        .position(x: geo.size.width * 0.85, y: geo.size.height * 0.9)
                        .blur(radius: 60)
                        .offset(x: ambientPhase ? -20 : 20, y: ambientPhase ? 15 : -15)
                }
            }
            .ignoresSafeArea()
            .animation(
                reduceMotion ? .default : .easeInOut(duration: 16).repeatForever(autoreverses: true),
                value: ambientPhase
            )
            .onAppear {
                guard !reduceMotion else { return }
                ambientPhase = true
            }
            .onChange(of: reduceMotion) { _, enabled in
                ambientPhase = !enabled
            }

            // Vignette for cinematic focus
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.65), location: 0.0),
                    .init(color: Color.black.opacity(0.20), location: 0.5),
                    .init(color: Color.black.opacity(0.70), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - View Modifiers for Fluid Glass UI

public extension View {
    /// Standard translucent glass card with specular edge and soft drop-shadow
    func glassCard(
        padding: CGFloat = Glass.cardPadding,
        radius: CGFloat = Glass.cardRadius,
        tint: Color = Theme.glassPanelBg,
        borderColor: Color? = nil
    ) -> some View {
        self
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(tint)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: (borderColor ?? Theme.specularBorder), location: 0.0),
                                .init(color: (borderColor?.opacity(0.4) ?? Theme.subtleBorder), location: 0.6),
                                .init(color: Color.white.opacity(0.04), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: Glass.strokeWidth
                    )
                    .blendMode(.plusLighter)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(
                color: Glass.shadowColor,
                radius: Glass.shadowRadius,
                x: 0,
                y: Glass.shadowYOffset
            )
    }

    /// Elevated panel for hero headers, dialogs, and prominent views
    func glassPanel(
        padding: CGFloat = Glass.panelPadding,
        radius: CGFloat = Glass.panelRadius,
        accentColor: Color? = nil
    ) -> some View {
        self
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Theme.glassElevatedBg)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    if let accent = accentColor {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.08), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: accentColor?.opacity(0.5) ?? Theme.specularGlowBorder, location: 0.0),
                                .init(color: Theme.specularBorder, location: 0.4),
                                .init(color: Color.white.opacity(0.05), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
                    .blendMode(.plusLighter)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Color.black.opacity(0.4), radius: 22, x: 0, y: 8)
    }

    /// High-tech floating HUD readout badge / capsule
    func glassCapsule(
        padding: Edge.Set = .horizontal,
        paddingAmount: CGFloat = 14,
        tint: Color = Theme.glassInteractiveBg
    ) -> some View {
        self
            .padding(padding, paddingAmount)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(tint)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [Theme.specularBorder, Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: Glass.strokeWidth
                            )
                            .blendMode(.plusLighter)
                    )
            )
            .shadow(color: Color.black.opacity(0.24), radius: 8, x: 0, y: 3)
    }

    /// Subtle colored glow on hover or active state
    func glassGlow(color: Color, radius: CGFloat = 12, opacity: Double = 0.4) -> some View {
        self.shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 0)
    }

    /// Primary text formatting
    func glassPrimary() -> some View {
        self.foregroundStyle(Theme.textPrimary)
    }

    /// Secondary text formatting
    func glassSecondary() -> some View {
        self.foregroundStyle(Theme.textSecondary)
    }

    /// Tertiary / muted text formatting
    func glassTertiary() -> some View {
        self.foregroundStyle(Theme.textTertiary)
    }

    /// Subtle floating drift
    func ambientDrift(amount: CGFloat = 8, duration: Double = 12) -> some View {
        self.modifier(AmbientDriftModifier(amount: amount, duration: duration))
    }
}

public struct AmbientDriftModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let amount: CGFloat
    let duration: Double
    @State private var phase: Bool = false

    public func body(content: Content) -> some View {
        content
            .offset(
                x: phase ? amount : -amount,
                y: phase ? -amount * 0.5 : amount * 0.5
            )
            .scaleEffect(phase ? 1.01 : 0.99)
            .animation(
                reduceMotion ? .default : .easeInOut(duration: duration).repeatForever(autoreverses: true),
                value: phase
            )
            .onAppear {
                guard !reduceMotion else { return }
                phase = true
            }
            .onChange(of: reduceMotion) { _, enabled in
                phase = !enabled
            }
    }
}

// MARK: - Modern 2026 Button Styles

public struct GlassProminentButtonStyle: ButtonStyle {
    public var color: Color = Theme.fujiAmber
    public var height: CGFloat = 38

    public init(color: Color = Theme.fujiAmber, height: CGFloat = 38) {
        self.color = color
        self.height = height
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color == Theme.fujiAmber || color == .white ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Glass.buttonRadius, style: .continuous)
                        .fill(color)
                    
                    // Gloss highlight
                    RoundedRectangle(cornerRadius: Glass.buttonRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                        .blendMode(.plusLighter)
                }
            )
            .shadow(
                color: color.opacity(configuration.isPressed ? 0.2 : 0.45),
                radius: configuration.isPressed ? 6 : 14,
                x: 0,
                y: configuration.isPressed ? 2 : 5
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

public struct GlassBorderedButtonStyle: ButtonStyle {
    public var accentColor: Color = .white
    public var height: CGFloat = 38

    public init(accentColor: Color = .white, height: CGFloat = 38) {
        self.accentColor = accentColor
        self.height = height
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(accentColor)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Glass.buttonRadius, style: .continuous)
                        .fill(configuration.isPressed ? Theme.glassActiveBg : Theme.glassInteractiveBg)
                    RoundedRectangle(cornerRadius: Glass.buttonRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: Glass.buttonRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [accentColor.opacity(0.35), Theme.subtleBorder],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: Glass.strokeWidth
                    )
                    .blendMode(.plusLighter)
            )
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.1 : 0.25),
                radius: configuration.isPressed ? 4 : 10,
                x: 0,
                y: configuration.isPressed ? 1 : 4
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

public struct GlassIconButton: View {
    let systemImage: String
    var title: String? = nil
    var tint: Color = Theme.textSecondary
    var activeColor: Color = Theme.fujiAmber
    var isActive: Bool = false
    var size: CGFloat = 32
    let action: () -> Void

    @State private var isHovered = false

    public init(
        systemImage: String,
        title: String? = nil,
        tint: Color = Theme.textSecondary,
        activeColor: Color = Theme.fujiAmber,
        isActive: Bool = false,
        size: CGFloat = 32,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.title = title
        self.tint = tint
        self.activeColor = activeColor
        self.isActive = isActive
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.42, weight: .semibold))
                if let title {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isActive ? activeColor : (isHovered ? Color.white : tint))
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, title != nil ? 8 : 0)
            .background(
                RoundedRectangle(cornerRadius: size / 3, style: .continuous)
                    .fill(isActive ? activeColor.opacity(0.18) : (isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.04)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size / 3, style: .continuous)
                    .stroke(isActive ? activeColor.opacity(0.4) : (isHovered ? Color.white.opacity(0.2) : Color.clear), lineWidth: 0.8)
                    .blendMode(.plusLighter)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title ?? systemImage)
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered || isActive)
    }
}

// MARK: - Responsive Section Header Component

public struct SectionHeader: View {
    public let title: String
    public var subtitle: String? = nil
    public var icon: String? = nil
    public var trailingValue: String? = nil
    public var trailingLabel: String? = nil
    public var accentColor: Color? = nil

    public init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        trailingValue: String? = nil,
        trailingLabel: String? = nil,
        accentColor: Color? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.trailingValue = trailingValue
        self.trailingLabel = trailingLabel
        self.accentColor = accentColor
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            // Standard horizontal arrangement
            HStack(alignment: .center, spacing: 12) {
                iconView
                titleGroup
                Spacer(minLength: 12)
                trailingBadge
            }
            // Vertical stacked arrangement for narrow views
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    iconView
                    titleGroup
                }
                trailingBadge
            }
        }
        .glassPanel(padding: 14, radius: Glass.panelRadius, accentColor: accentColor)
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((accentColor ?? Theme.fujiAmber).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentColor ?? Theme.fujiAmber)
            }
        }
    }

    private var titleGroup: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.bold))
                .glassPrimary()
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .glassSecondary()
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var trailingBadge: some View {
        if let trailingValue {
            VStack(alignment: .trailing, spacing: 1) {
                Text(trailingValue)
                    .font(.subheadline.weight(.bold))
                    .glassPrimary()
                    .contentTransition(.numericText(countsDown: false))
                if let trailingLabel {
                    Text(trailingLabel)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .glassSecondary()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }
}

// MARK: - Fluid Sliding Pill Toggle / Segmented Picker

public struct GlassPillToggle<Value: Hashable>: View {
    public let options: [(value: Value, label: String)]
    @Binding public var selection: Value
    public var accentColor: Color = Theme.fujiAmber

    public init(
        options: [(value: Value, label: String)],
        selection: Binding<Value>,
        accentColor: Color = Theme.fujiAmber
    ) {
        self.options = options
        self._selection = selection
        self.accentColor = accentColor
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isSelected = selection == option.value
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(.caption.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.black : Theme.textSecondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .lineLimit(1)
                        .background(
                            ZStack {
                                if isSelected {
                                    Capsule()
                                        .fill(accentColor)
                                        .matchedGeometryEffect(id: "activePill", in: pillNamespace)
                                        .shadow(color: accentColor.opacity(0.35), radius: 6, y: 2)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            Capsule()
                .fill(Theme.glassInteractiveBg)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(
                    Capsule()
                        .stroke(Theme.specularBorder, lineWidth: Glass.strokeWidth)
                        .blendMode(.plusLighter)
                )
        )
    }

    @Namespace private var pillNamespace
}

// MARK: - Visual Tone Curve Mini Radar / Offsets Indicator

public struct ToneCurveRadar: View {
    public let highlight: Int32?
    public let shadow: Int32?
    public let color: Int32?
    public let sharpness: Int32?
    public var accentColor: Color = Theme.fujiAmber

    public init(
        highlight: Int32? = nil,
        shadow: Int32? = nil,
        color: Int32? = nil,
        sharpness: Int32? = nil,
        accentColor: Color = Theme.fujiAmber
    ) {
        self.highlight = highlight
        self.shadow = shadow
        self.color = color
        self.sharpness = sharpness
        self.accentColor = accentColor
    }

    public var body: some View {
        HStack(spacing: 5) {
            toneBar(label: "H", value: highlight ?? 0)
            toneBar(label: "S", value: shadow ?? 0)
            toneBar(label: "C", value: color ?? 0)
            toneBar(label: "Sh", value: sharpness ?? 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.6)
                )
        )
    }

    private func toneBar(label: String, value: Int32) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
            
            Text(value == 0 ? "0" : (value > 0 ? "+\(value)" : "\(value)"))
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(value == 0 ? Theme.textTertiary : (value > 0 ? accentColor : Theme.cyanAccent))
        }
        .frame(minWidth: 15)
    }
}

// MARK: - Kelvin Color Chip (Visual White Balance Planckian Radiator)

public struct KelvinChip: View {
    public let kelvin: UInt32?
    public let modeName: String?

    public init(kelvin: UInt32?, modeName: String? = nil) {
        self.kelvin = kelvin
        self.modeName = modeName
    }

    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(kelvinColor)
                .frame(width: 6, height: 6)
                .shadow(color: kelvinColor.opacity(0.8), radius: 2)
            
            if let k = kelvin, k > 0 {
                Text("\(k)K")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            } else if let modeName {
                Text(modeName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            } else {
                Text("Auto WB")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.3))
                .overlay(
                    Capsule()
                        .stroke(kelvinColor.opacity(0.3), lineWidth: 0.7)
                )
        )
    }

    private var kelvinColor: Color {
        guard let k = kelvin, k > 0 else {
            return Color(red: 0.90, green: 0.90, blue: 0.95)
        }
        if k < 3500 {
            return Color(red: 1.0, green: 0.60, blue: 0.25)
        } else if k < 5000 {
            return Color(red: 1.0, green: 0.85, blue: 0.55)
        } else if k <= 6500 {
            return Color(red: 0.95, green: 0.95, blue: 1.0)
        } else {
            return Color(red: 0.70, green: 0.85, blue: 1.0)
        }
    }
}

// MARK: - Film Simulation Badge

public struct FilmSimBadge: View {
    public let name: String
    public var isCompact: Bool = false

    public init(name: String, isCompact: Bool = false) {
        self.name = name
        self.isCompact = isCompact
    }

    private var accent: Color {
        Theme.filmSimColor(for: name)
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "film")
                .font(.system(size: isCompact ? 8 : 9, weight: .bold))
                .foregroundStyle(accent)

            Text(name)
                .font(isCompact ? .system(size: 9, weight: .semibold) : .caption2.weight(.bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
        .padding(.horizontal, isCompact ? 6 : 8)
        .padding(.vertical, isCompact ? 2 : 4)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(accent.opacity(0.20))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(accent.opacity(0.45), lineWidth: 0.8)
                    .blendMode(.plusLighter)
            }
        )
    }
}

// MARK: - Extension conveniences for backward compatibility

public extension ButtonStyle where Self == GlassProminentButtonStyle {
    static var glassProminent: GlassProminentButtonStyle { GlassProminentButtonStyle() }
}

public extension ButtonStyle where Self == GlassBorderedButtonStyle {
    static var glassBordered: GlassBorderedButtonStyle { GlassBorderedButtonStyle() }
}
