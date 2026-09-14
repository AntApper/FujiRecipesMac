import SwiftUI
import FujiRecipesCore

/// A focused editor for the fields the C-slot writer understands. Defaults are
/// intentionally valid X100VI values, so every new recipe can use Send to Dial.
struct CustomRecipeEditor: View {
    let recipe: Recipe
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

    init(recipe: Recipe, onSave: @escaping (Recipe) -> Void) {
        self.recipe = recipe
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

    var body: some View {
        Form {
            Section("Recipe") {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("custom-recipe-name")
                TextField("Attribution (optional)", text: $source)
                    .accessibilityIdentifier("custom-recipe-source")
                Picker("Film Simulation", selection: $filmSimulation) {
                    ForEach(FilmSimulation.allCases, id: \.rawValue) {
                        Text($0.displayName).tag($0.rawValue)
                    }
                }
                .accessibilityIdentifier("custom-recipe-film-simulation")
            }

            Section("Exposure and Color") {
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
                if whiteBalance == WhiteBalanceMode.colorTemperature.rawValue {
                    Stepper("Kelvin: \(colorTemperature) K", value: $colorTemperature, in: 2_500...10_000, step: 100)
                        .accessibilityIdentifier("custom-recipe-kelvin")
                }
                Stepper("WB Red Shift: \(redShift)", value: $redShift, in: -9...9)
                Stepper("WB Blue Shift: \(blueShift)", value: $blueShift, in: -9...9)
            }

            Section("Tone") {
                Stepper("Highlight: \(highlight)", value: $highlight, in: -2...4)
                Stepper("Shadow: \(shadow)", value: $shadow, in: -2...4)
                Stepper("Color: \(color)", value: $color, in: -4...4)
                Stepper("Sharpness: \(sharpness)", value: $sharpness, in: -4...4)
                Stepper("High ISO NR: \(highIsoNR)", value: $highIsoNR, in: -4...4)
                Stepper("Clarity: \(clarity)", value: $clarity, in: -5...5)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 560)
        .navigationTitle(recipe.name.isEmpty ? "New Custom Recipe" : "Edit Custom Recipe")
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
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("custom-recipe-save")
            }
        }
    }

    private func makeRecipe() -> Recipe {
        let sim = FilmSimulation(rawValue: filmSimulation) ?? .provia
        let dr = DynamicRange(rawValue: dynamicRange) ?? .dr100
        let selectedGrain = GrainEffect(rawValue: grain) ?? .off
        let wb = WhiteBalanceMode(rawValue: whiteBalance) ?? .auto
        let settings = [
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
        return Recipe(
            id: recipe.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My Recipes" : source,
            sourceUrl: nil,
            filmSimulation: sim,
            dynamicRange: dr,
            grainEffect: selectedGrain,
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
            settings: settings,
            sensorGeneration: "X-Trans V",
            compatibleCameras: ["X100VI"],
            tags: ["My Recipes"],
            parseStatus: .ok
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
