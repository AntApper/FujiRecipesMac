import SwiftUI
import FujiRecipesCore

/// A focused editor for the fields the C-slot writer understands. Defaults are
/// intentionally valid X100VI values, so every new recipe can use Send to Dial.
struct CustomRecipeEditor: View {
    let recipe: Recipe
    let existingRecipes: [Recipe]
    let onSave: (Recipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var source: String
    @State private var filmSimulation: UInt32
    @State private var dynamicRange: UInt32
    @State private var grain: UInt32
    @State private var whiteBalance: UInt32
    @State private var colorTemperature: Int
    @State private var redShift: Int
    @State private var blueShift: Int
    @State private var highlight: Int
    @State private var shadow: Int
    @State private var color: Int
    @State private var sharpness: Int
    @State private var highIsoNR: Int
    @State private var clarity: Int

    init(
        recipe: Recipe,
        existingRecipes: [Recipe] = [],
        onSave: @escaping (Recipe) -> Void
    ) {
        self.recipe = recipe
        self.existingRecipes = existingRecipes
        self.onSave = onSave
        _name = State(initialValue: recipe.name)
        _source = State(initialValue: recipe.source == "My Recipes" ? "" : recipe.source)
        _filmSimulation = State(initialValue: recipe.filmSimulation?.rawValue ?? FilmSimulation.provia.rawValue)
        _dynamicRange = State(initialValue: recipe.dynamicRange?.rawValue ?? DynamicRange.dr100.rawValue)
        _grain = State(initialValue: recipe.grainEffect?.rawValue ?? GrainEffect.off.rawValue)
        _whiteBalance = State(initialValue: recipe.whiteBalanceMode?.rawValue ?? WhiteBalanceMode.auto.rawValue)
        _colorTemperature = State(initialValue: Int(recipe.colorTempK ?? 5_600))
        _redShift = State(initialValue: Int(recipe.wbShiftRed ?? 0))
        _blueShift = State(initialValue: Int(recipe.wbShiftBlue ?? 0))
        _highlight = State(initialValue: Int(recipe.highlight ?? 0))
        _shadow = State(initialValue: Int(recipe.shadow ?? 0))
        _color = State(initialValue: Int(recipe.color ?? 0))
        _sharpness = State(initialValue: Int(recipe.sharpness ?? 0))
        _highIsoNR = State(initialValue: Int(recipe.highIsoNr ?? 0))
        _clarity = State(initialValue: Int(recipe.clarity ?? 0))
    }

    static func newRecipe() -> Recipe {
        Recipe(
            id: "custom-\(UUID().uuidString.lowercased())",
            name: "",
            source: "My Recipes",
            sourceUrl: nil,
            filmSimulation: .provia,
            dynamicRange: .dr100,
            grainEffect: .off,
            whiteBalanceMode: .auto,
            wbShiftRed: 0,
            wbShiftBlue: 0,
            highlight: 0,
            shadow: 0,
            color: 0,
            sharpness: 0,
            highIsoNr: 0,
            clarity: 0,
            settings: [:],
            sensorGeneration: "X-Trans V",
            compatibleCameras: ["X100VI"],
            tags: ["My Recipes"]
        )
    }

    static func duplicate(from recipe: Recipe) -> Recipe {
        recipe.duplicated()
    }

    // MARK: - Real-Time Validation

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isNameEmpty: Bool {
        trimmedName.isEmpty
    }

    private var conflictingRecipe: Recipe? {
        guard !isNameEmpty else { return nil }
        return existingRecipes.first { existing in
            existing.id != recipe.id &&
            existing.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    private var isValid: Bool {
        !isNameEmpty && conflictingRecipe == nil
    }

    private var currentSimName: String {
        FilmSimulation(rawValue: filmSimulation)?.displayName ?? "Provia"
    }

    private var currentSimColor: Color {
        Theme.filmSimColor(for: currentSimName)
    }

    // MARK: - Body

    var body: some View {
        Form {
            // Section 1: Recipe Identity & Validation
            Section("Recipe Identity") {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("custom-recipe-name")

                    validationStatusView
                }

                TextField("Attribution (optional)", text: $source)
                    .accessibilityIdentifier("custom-recipe-source")
            }

            // Section 2: Visual Film Simulation Picker
            Section("Film Simulation") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Film Simulation", selection: $filmSimulation) {
                        ForEach(FilmSimulation.allCases, id: \.rawValue) {
                            Text($0.displayName).tag($0.rawValue)
                        }
                    }
                    .accessibilityIdentifier("custom-recipe-film-simulation")

                    // Visual simulation color chips & badges carousel
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(FilmSimulation.allCases, id: \.rawValue) { sim in
                                let isSelected = filmSimulation == sim.rawValue
                                let simColor = Theme.filmSimColor(for: sim.displayName)

                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        filmSimulation = sim.rawValue
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(simColor)
                                            .frame(width: 8, height: 8)
                                            .shadow(color: simColor.opacity(isSelected ? 0.9 : 0.4), radius: isSelected ? 3 : 1)

                                        Text(sim.displayName)
                                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                            .foregroundStyle(isSelected ? Color.white : Theme.textSecondary)
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(isSelected ? simColor.opacity(0.22) : Color.white.opacity(0.04))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(isSelected ? simColor : Color.white.opacity(0.10), lineWidth: isSelected ? 1.2 : 0.7)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // Section 3: Exposure, Grain & White Balance
            Section("Exposure and White Balance") {
                Picker("Dynamic Range", selection: $dynamicRange) {
                    ForEach(dynamicRangeOptions, id: \.rawValue) { option in
                        Text(option.name).tag(option.rawValue)
                    }
                }

                Picker("Grain", selection: $grain) {
                    ForEach(grainOptions, id: \.rawValue) { option in
                        Text(option.name).tag(option.rawValue)
                    }
                }

                Picker("White Balance", selection: $whiteBalance) {
                    ForEach(whiteBalanceOptions, id: \.rawValue) { option in
                        Text(option.name).tag(option.rawValue)
                    }
                }

                // Planckian Radiator Kelvin Slider & Color Chip
                if whiteBalance == WhiteBalanceMode.colorTemperature.rawValue {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Color Temperature")
                                .font(.subheadline)
                            Spacer()
                            KelvinChip(kelvin: UInt32(colorTemperature))
                        }

                        // Planckian spectrum visualization track
                        VStack(spacing: 4) {
                            Slider(
                                value: Binding(
                                    get: { Double(colorTemperature) },
                                    set: { colorTemperature = Int((round($0 / 100.0)) * 100) }
                                ),
                                in: 2500...10000,
                                step: 100
                            )

                            // Continuous Planckian Blackbody spectrum gradient
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 1.0, green: 0.55, blue: 0.20), // 2500K Candle/Tungsten
                                            Color(red: 1.0, green: 0.75, blue: 0.40), // 3500K Warm
                                            Color(red: 1.0, green: 0.88, blue: 0.60), // 4800K Sunlight
                                            Color(red: 0.96, green: 0.96, blue: 1.00), // 6500K Daylight White
                                            Color(red: 0.75, green: 0.88, blue: 1.00), // 8500K Blue Sky
                                            Color(red: 0.60, green: 0.80, blue: 1.00)  // 10000K Deep Cool
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(height: 5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                                )

                            HStack {
                                Text("2500K")
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color(red: 1.0, green: 0.60, blue: 0.25))
                                Spacer()
                                Text("5600K (Daylight)")
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color(red: 0.95, green: 0.95, blue: 1.0))
                                Spacer()
                                Text("10000K")
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color(red: 0.70, green: 0.85, blue: 1.0))
                            }
                        }

                        Stepper("Kelvin: \(colorTemperature) K", value: $colorTemperature, in: 2_500...10_000, step: 100)
                            .accessibilityIdentifier("custom-recipe-kelvin")
                    }
                    .padding(.vertical, 4)
                }

                Stepper("WB Red Shift: \(signed(redShift))", value: $redShift, in: -9...9)
                Stepper("WB Blue Shift: \(signed(blueShift))", value: $blueShift, in: -9...9)
            }

            // Section 4: Interactive Tone Curve Radar Preview & Tuning
            Section("Tone Curve & Offsets") {
                VStack(spacing: 14) {
                    // Real-Time Interactive Radar Canvas
                    InteractiveToneRadarView(
                        highlight: highlight,
                        shadow: shadow,
                        color: color,
                        sharpness: sharpness,
                        accentColor: currentSimColor
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)

                    Divider().overlay(Color.white.opacity(0.08))

                    // Live Parameter Steppers
                    VStack(spacing: 6) {
                        Stepper("Highlight: \(signed(highlight))", value: $highlight, in: -2...4)
                        Stepper("Shadow: \(signed(shadow))", value: $shadow, in: -2...4)
                        Stepper("Color: \(signed(color))", value: $color, in: -4...4)
                        Stepper("Sharpness: \(signed(sharpness))", value: $sharpness, in: -4...4)
                        Stepper("High ISO NR: \(signed(highIsoNR))", value: $highIsoNR, in: -4...4)
                        Stepper("Clarity: \(signed(clarity))", value: $clarity, in: -5...5)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, minHeight: 620)
        .navigationTitle(recipe.source.starts(with: "Customized from") ? "Customize Recipe" : (recipe.name.isEmpty ? "New Custom Recipe" : "Edit Custom Recipe"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("custom-recipe-cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(makeRecipe())
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
                .accessibilityIdentifier("custom-recipe-save")
            }
        }
    }

    // MARK: - Validation View

    private var validationStatusView: some View {
        Group {
            if isNameEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Theme.fujiAmber)
                    Text("Recipe name is required")
                        .font(.caption2)
                        .foregroundStyle(Theme.fujiAmber)
                }
            } else if let conflict = conflictingRecipe {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.fujiRed)
                    Text("Name conflicts with existing recipe \"\(conflict.name)\"")
                        .font(.caption2)
                        .foregroundStyle(Theme.fujiRed)
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.emeraldGreen)
                    Text("Valid name & unique identifier")
                        .font(.caption2)
                        .foregroundStyle(Theme.emeraldGreen)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: name)
    }

    private func makeRecipe() -> Recipe {
        let sim = FilmSimulation(rawValue: filmSimulation) ?? .provia
        let dr = DynamicRange(rawValue: dynamicRange) ?? .dr100
        let selectedGrain = GrainEffect(rawValue: grain) ?? .off
        let wb = WhiteBalanceMode(rawValue: whiteBalance) ?? .auto
        let editedSettings = [
            "filmSimulation": sim.displayName,
            "dynamicRange": dr.displayName,
            "grainEffect": selectedGrain.displayName,
            "whiteBalance": wb.displayName,
            "highlight": signed(highlight),
            "shadow": signed(shadow),
            "color": signed(color),
            "sharpness": signed(sharpness),
            "highIsoNr": signed(highIsoNR),
            "clarity": signed(clarity)
        ]
        // Half-step values live only in the raw preset, so keep each raw value
        // until the user moves that slider off its initial whole-step value.
        var rawPreset = recipe.sourceRawPreset
        if highlight != Int(recipe.highlight ?? 0) { rawPreset?.highlight = nil }
        if shadow != Int(recipe.shadow ?? 0) { rawPreset?.shadow = nil }
        if color != Int(recipe.color ?? 0) { rawPreset?.color = nil }
        if sharpness != Int(recipe.sharpness ?? 0) { rawPreset?.sharpness = nil }
        if clarity != Int(recipe.clarity ?? 0) { rawPreset?.clarity = nil }

        return Recipe(
            id: recipe.id,
            name: trimmedName,
            source: source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My Recipes" : source,
            sourceUrl: recipe.sourceUrl,
            previewImageUrl: recipe.previewImageUrl,
            imageUrls: recipe.imageUrls,
            date: recipe.date,
            dateString: recipe.dateString,
            filmSimulation: sim,
            dynamicRange: dr,
            grainEffect: selectedGrain,
            colorChrome: recipe.colorChrome,
            colorChromeFxBlue: recipe.colorChromeFxBlue,
            smoothSkin: recipe.smoothSkin,
            whiteBalanceMode: wb,
            wbShiftRed: Int32(redShift),
            wbShiftBlue: Int32(blueShift),
            colorTempK: wb == .colorTemperature ? UInt32(colorTemperature) : nil,
            highlight: Int32(highlight),
            shadow: Int32(shadow),
            color: Int32(color),
            sharpness: Int32(sharpness),
            highIsoNr: Int32(highIsoNR),
            clarity: Int32(clarity),
            iso: recipe.iso,
            exposureCompensation: recipe.exposureCompensation,
            settings: (recipe.settings ?? [:]).merging(editedSettings) { _, edited in edited },
            sensorGeneration: "X-Trans V",
            compatibleCameras: ["X100VI"],
            tags: ["My Recipes"],
            parseStatus: .ok,
            sourceRawPreset: rawPreset?.hasAnyValue == true ? rawPreset : nil
        )
    }

    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }

    private let dynamicRangeOptions = [
        (name: "Auto", rawValue: DynamicRange.auto.rawValue),
        (name: "DR100", rawValue: DynamicRange.dr100.rawValue),
        (name: "DR200", rawValue: DynamicRange.dr200.rawValue),
        (name: "DR400", rawValue: DynamicRange.dr400.rawValue)
    ]
    private let grainOptions = [
        (name: "Off", rawValue: GrainEffect.off.rawValue),
        (name: "Weak, Small", rawValue: GrainEffect.weakSmall.rawValue),
        (name: "Strong, Small", rawValue: GrainEffect.strongSmall.rawValue),
        (name: "Weak, Large", rawValue: GrainEffect.weakLarge.rawValue),
        (name: "Strong, Large", rawValue: GrainEffect.strongLarge.rawValue)
    ]
    private let whiteBalanceOptions = [
        (name: "Auto (AWB)", rawValue: WhiteBalanceMode.auto.rawValue),
        (name: "Daylight", rawValue: WhiteBalanceMode.daylight.rawValue),
        (name: "Cloudy", rawValue: WhiteBalanceMode.cloudy.rawValue),
        (name: "Shade", rawValue: WhiteBalanceMode.shade.rawValue),
        (name: "Tungsten", rawValue: WhiteBalanceMode.tungsten.rawValue),
        (name: "Color Temperature", rawValue: WhiteBalanceMode.colorTemperature.rawValue)
    ]
}

// MARK: - Interactive Tone Curve Radar Preview

struct InteractiveToneRadarView: View {
    let highlight: Int
    let shadow: Int
    let color: Int
    let sharpness: Int
    var accentColor: Color = Theme.fujiAmber

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RadarCanvas(
                    highlight: highlight,
                    shadow: shadow,
                    color: color,
                    sharpness: sharpness,
                    accentColor: accentColor
                )
                .frame(width: 180, height: 180)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )

            // Real-Time Metric Badges
            HStack(spacing: 8) {
                metricPill(label: "H", value: highlight)
                metricPill(label: "S", value: shadow)
                metricPill(label: "C", value: color)
                metricPill(label: "Sh", value: sharpness)
            }
        }
    }

    private func metricPill(label: String, value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
            Text(value > 0 ? "+\(value)" : "\(value)")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(value == 0 ? Theme.textTertiary : (value > 0 ? accentColor : Theme.cyanAccent))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.6))
    }
}

// MARK: - 120Hz ProMotion Radar Canvas

struct RadarCanvas: View {
    let highlight: Int
    let shadow: Int
    let color: Int
    let sharpness: Int
    let accentColor: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxR: CGFloat = min(size.width, size.height) / 2 - 18
            let neutralR: CGFloat = maxR * 0.45
            let minR: CGFloat = 8

            // 1. Min boundary circle
            let minPath = Circle().path(in: CGRect(x: center.x - minR, y: center.y - minR, width: minR * 2, height: minR * 2))
            context.stroke(minPath, with: .color(Color.white.opacity(0.08)), lineWidth: 0.6)

            // 2. Neutral baseline ring (dashed)
            let neutralPath = Circle().path(in: CGRect(x: center.x - neutralR, y: center.y - neutralR, width: neutralR * 2, height: neutralR * 2))
            context.stroke(neutralPath, with: .color(Color.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            // 3. Max boundary circle
            let maxPath = Circle().path(in: CGRect(x: center.x - maxR, y: center.y - maxR, width: maxR * 2, height: maxR * 2))
            context.stroke(maxPath, with: .color(Color.white.opacity(0.10)), lineWidth: 0.8)

            // 4. Orthogonal crosshairs
            var crossPath = Path()
            crossPath.move(to: CGPoint(x: center.x, y: center.y - maxR))
            crossPath.addLine(to: CGPoint(x: center.x, y: center.y + maxR))
            crossPath.move(to: CGPoint(x: center.x - maxR, y: center.y))
            crossPath.addLine(to: CGPoint(x: center.x + maxR, y: center.y))
            context.stroke(crossPath, with: .color(Color.white.opacity(0.10)), lineWidth: 0.8)

            // Compute Vertices:
            // Top: Highlight [-2, +4]
            let rH: CGFloat
            if highlight >= 0 {
                rH = neutralR + CGFloat(highlight) / 4.0 * (maxR - neutralR)
            } else {
                rH = neutralR - CGFloat(-highlight) / 2.0 * (neutralR - minR)
            }
            let pTop = CGPoint(x: center.x, y: center.y - rH)

            // Right: Color [-4, +4]
            let rC: CGFloat
            if color >= 0 {
                rC = neutralR + CGFloat(color) / 4.0 * (maxR - neutralR)
            } else {
                rC = neutralR - CGFloat(-color) / 4.0 * (neutralR - minR)
            }
            let pRight = CGPoint(x: center.x + rC, y: center.y)

            // Bottom: Shadow [-2, +4]
            let rS: CGFloat
            if shadow >= 0 {
                rS = neutralR + CGFloat(shadow) / 4.0 * (maxR - neutralR)
            } else {
                rS = neutralR - CGFloat(-shadow) / 2.0 * (neutralR - minR)
            }
            let pBottom = CGPoint(x: center.x, y: center.y + rS)

            // Left: Sharpness [-4, +4]
            let rSh: CGFloat
            if sharpness >= 0 {
                rSh = neutralR + CGFloat(sharpness) / 4.0 * (maxR - neutralR)
            } else {
                rSh = neutralR - CGFloat(-sharpness) / 4.0 * (neutralR - minR)
            }
            let pLeft = CGPoint(x: center.x - rSh, y: center.y)

            // Draw filled polygon
            var polyPath = Path()
            polyPath.move(to: pTop)
            polyPath.addLine(to: pRight)
            polyPath.addLine(to: pBottom)
            polyPath.addLine(to: pLeft)
            polyPath.closeSubpath()

            context.fill(polyPath, with: .color(accentColor.opacity(0.24)))
            context.stroke(polyPath, with: .color(accentColor), lineWidth: 2)

            // Draw glowing vertex nodes
            let vertices = [pTop, pRight, pBottom, pLeft]
            for v in vertices {
                let nodeRect = CGRect(x: v.x - 3.5, y: v.y - 3.5, width: 7, height: 7)
                context.fill(Circle().path(in: nodeRect), with: .color(Color.white))
                context.stroke(Circle().path(in: nodeRect), with: .color(accentColor), lineWidth: 1.5)
            }

            // Draw axis labels
            context.draw(
                Text("H").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textSecondary),
                at: CGPoint(x: center.x, y: center.y - maxR - 8)
            )
            context.draw(
                Text("C").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textSecondary),
                at: CGPoint(x: center.x + maxR + 9, y: center.y)
            )
            context.draw(
                Text("S").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textSecondary),
                at: CGPoint(x: center.x, y: center.y + maxR + 8)
            )
            context.draw(
                Text("Sh").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textSecondary),
                at: CGPoint(x: center.x - maxR - 9, y: center.y)
            )
        }
    }
}
