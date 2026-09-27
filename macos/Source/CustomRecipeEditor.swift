import SwiftUI
import FujiRecipesCore

/// A focused editor for the fields the C-slot writer understands. Defaults are
/// intentionally valid X100VI values, so every new recipe can use Send to Dial.
/// A field the recipe leaves unset stays "Not set" until the user picks a value.
struct CustomRecipeEditor: View {
    let recipe: Recipe
    let existingRecipes: [Recipe]
    let onSave: (Recipe) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var saveError: String?
    @State private var name: String
    @State private var source: String
    @State private var filmSimulation: UInt32?
    @State private var dynamicRange: UInt32?
    @State private var grain: UInt32?
    @State private var whiteBalance: UInt32?
    @State private var colorTemperature: Int
    @State private var redShift: Int?
    @State private var blueShift: Int?
    /// Highlight and shadow are C-slot tenths so they can hold half steps.
    @State private var highlight: Int?
    @State private var shadow: Int?
    @State private var color: Int?
    @State private var sharpness: Int?
    @State private var highIsoNR: Int?
    @State private var clarity: Int?

    init(
        recipe: Recipe,
        existingRecipes: [Recipe] = [],
        onSave: @escaping (Recipe) throws -> Void
    ) {
        self.recipe = recipe
        self.existingRecipes = existingRecipes
        self.onSave = onSave
        _name = State(initialValue: recipe.name)
        _source = State(initialValue: recipe.source == "My Recipes" ? "" : recipe.source)
        _filmSimulation = State(initialValue: recipe.filmSimulation?.rawValue)
        _dynamicRange = State(initialValue: recipe.dynamicRange?.rawValue)
        _grain = State(initialValue: recipe.grainEffect?.rawValue)
        _whiteBalance = State(initialValue: recipe.whiteBalanceMode?.rawValue)
        _colorTemperature = State(initialValue: Int(recipe.colorTempK ?? CSlotPresetEncoder.defaultColorTemperature))
        _redShift = State(initialValue: recipe.wbShiftRed.map(Int.init))
        _blueShift = State(initialValue: recipe.wbShiftBlue.map(Int.init))
        _highlight = State(initialValue: recipe.toneTenths.highlight.map(Int.init))
        _shadow = State(initialValue: recipe.toneTenths.shadow.map(Int.init))
        _color = State(initialValue: recipe.color.map(Int.init))
        _sharpness = State(initialValue: recipe.sharpness.map(Int.init))
        _highIsoNR = State(initialValue: recipe.highIsoNr.map(Int.init))
        _clarity = State(initialValue: recipe.clarity.map(Int.init))
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
        filmSimulation.flatMap(FilmSimulation.init(rawValue:))?.displayName ?? "Provia"
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
                        Text("Not set").tag(UInt32?.none)
                        ForEach(FilmSimulation.allCases, id: \.rawValue) {
                            Text($0.displayName).tag(Optional($0.rawValue))
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
                    Text("Not set").tag(UInt32?.none)
                    ForEach(dynamicRangeOptions, id: \.rawValue) { option in
                        Text(option.name).tag(Optional(option.rawValue))
                    }
                }

                Picker("Grain", selection: $grain) {
                    Text("Not set").tag(UInt32?.none)
                    ForEach(grainOptions, id: \.rawValue) { option in
                        Text(option.name).tag(Optional(option.rawValue))
                    }
                }

                Picker("White Balance", selection: $whiteBalance) {
                    Text("Not set").tag(UInt32?.none)
                    ForEach(whiteBalanceOptions, id: \.rawValue) { option in
                        Text(option.displayName).tag(Optional(option.rawValue))
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

                optionalStepper("WB Red Shift", $redShift, in: -9...9)
                optionalStepper("WB Blue Shift", $blueShift, in: -9...9)
            }

            // Section 4: Interactive Tone Curve Radar Preview & Tuning
            Section("Tone Curve & Offsets") {
                VStack(spacing: 14) {
                    // Real-Time Interactive Radar Canvas
                    InteractiveToneRadarView(tones: editedTones, accentColor: currentSimColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)

                    Divider().overlay(Color.white.opacity(0.08))

                    // Live Parameter Steppers
                    VStack(spacing: 6) {
                        optionalStepper("Highlight", $highlight, in: halfStepRange, step: 5, format: toneText)
                        optionalStepper("Shadow", $shadow, in: halfStepRange, step: 5, format: toneText)
                        optionalStepper("Color", $color, in: -4...4)
                        optionalStepper("Sharpness", $sharpness, in: -4...4)
                        optionalStepper("High ISO NR", $highIsoNR, in: -4...4)
                        optionalStepper("Clarity", $clarity, in: -5...5)
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
                    do {
                        try onSave(makeRecipe())
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
                .accessibilityIdentifier("custom-recipe-save")
            }
        }
        .alert("Couldn’t Save Recipe", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
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

    /// Shows "Not set" until the first step, which starts from 0.
    private func optionalStepper(
        _ title: String,
        _ value: Binding<Int?>,
        in range: ClosedRange<Int>,
        step: Int = 1,
        format: @escaping (Int) -> String = { $0 > 0 ? "+\($0)" : "\($0)" }
    ) -> some View {
        Stepper(
            "\(title): \(value.wrappedValue.map(format) ?? "Not set")",
            value: Binding(get: { value.wrappedValue ?? 0 }, set: { value.wrappedValue = $0 }),
            in: range,
            step: step
        )
    }

    private func toneText(_ tenths: Int) -> String {
        ToneTenths.text(Int32(tenths))
    }

    private var halfStepRange: ClosedRange<Int> {
        Int(CSlotPresetEncoder.highlightShadowRange.lowerBound * 10)...Int(CSlotPresetEncoder.highlightShadowRange.upperBound * 10)
    }

    private var editedTones: ToneTenths {
        makeRecipe().toneTenths
    }

    private func makeRecipe() -> Recipe {
        let sim = filmSimulation.flatMap(FilmSimulation.init(rawValue:))
        let dr = dynamicRange.flatMap(DynamicRange.init(rawValue:))
        let selectedGrain = grain.flatMap(GrainEffect.init(rawValue:))
        let wb = whiteBalance.flatMap(WhiteBalanceMode.init(rawValue:))
        let editedSettings: [String: String?] = [
            "filmSimulation": sim?.displayName,
            "dynamicRange": dr?.displayName,
            "grainEffect": selectedGrain?.displayName,
            "whiteBalance": wb?.displayName,
            "highlight": highlight.map(toneText),
            "shadow": shadow.map(toneText),
            "color": color.map(signed),
            "sharpness": sharpness.map(signed),
            "highIsoNr": highIsoNR.map(signed),
            "clarity": clarity.map(signed)
        ]
        var settings = recipe.settings ?? [:]
        for (key, text) in editedSettings {
            settings[key] = text
        }
        // Whole-step fields cannot hold a half step, so highlight and shadow
        // keep one in the raw preset. Other raw values last until the user
        // moves that stepper off its initial whole-step value.
        var rawPreset = recipe.sourceRawPreset ?? LoadoutRawPresetState()
        rawPreset.highlight = highlight.flatMap { $0 % 10 == 0 ? nil : Int32($0) }
        rawPreset.shadow = shadow.flatMap { $0 % 10 == 0 ? nil : Int32($0) }
        if color != recipe.color.map(Int.init) { rawPreset.color = nil }
        if sharpness != recipe.sharpness.map(Int.init) { rawPreset.sharpness = nil }
        if clarity != recipe.clarity.map(Int.init) { rawPreset.clarity = nil }

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
            wbShiftRed: redShift.map(Int32.init),
            wbShiftBlue: blueShift.map(Int32.init),
            colorTempK: wb == .colorTemperature ? UInt32(colorTemperature) : nil,
            highlight: highlight.map { Int32($0 / 10) },
            shadow: shadow.map { Int32($0 / 10) },
            color: color.map(Int32.init),
            sharpness: sharpness.map(Int32.init),
            highIsoNr: highIsoNR.map(Int32.init),
            clarity: clarity.map(Int32.init),
            iso: recipe.iso,
            exposureCompensation: recipe.exposureCompensation,
            settings: settings,
            sensorGeneration: "X-Trans V",
            compatibleCameras: ["X100VI"],
            tags: ["My Recipes"],
            parseStatus: .ok,
            sourceRawPreset: rawPreset.hasAnyValue ? rawPreset : nil
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
    private let whiteBalanceOptions = WhiteBalanceMode.cameraModes
}

// MARK: - Interactive Tone Curve Radar Preview

struct InteractiveToneRadarView: View {
    let tones: ToneTenths
    var accentColor: Color = Theme.fujiAmber

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RadarCanvas(tones: tones, accentColor: accentColor)
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
                metricPill(label: "H", tenths: tones.highlight)
                metricPill(label: "S", tenths: tones.shadow)
                metricPill(label: "C", tenths: tones.color)
                metricPill(label: "Sh", tenths: tones.sharpness)
            }
        }
    }

    private func metricPill(label: String, tenths value: Int32?) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
            Text(value.map(ToneTenths.text) ?? "·")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle((value ?? 0) == 0 ? Theme.textTertiary : ((value ?? 0) > 0 ? accentColor : Theme.cyanAccent))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.6))
    }
}

// MARK: - 120Hz ProMotion Radar Canvas

struct RadarCanvas: View {
    let tones: ToneTenths
    let accentColor: Color

    var body: some View {
        Canvas { context, size in
            let highlight = CGFloat(tones.highlight ?? 0) / 10
            let shadow = CGFloat(tones.shadow ?? 0) / 10
            let color = CGFloat(tones.color ?? 0) / 10
            let sharpness = CGFloat(tones.sharpness ?? 0) / 10
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
