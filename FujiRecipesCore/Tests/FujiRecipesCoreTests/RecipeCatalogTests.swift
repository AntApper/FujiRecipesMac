import XCTest
@testable import FujiRecipesCore

final class RecipeCatalogTests: XCTestCase {
    func testSearchNormalizesCaseDiacriticsAndMultipleTerms() {
        let catalog = RecipeCatalog(recipes: [
            recipe(name: "Café Street", filmSimulation: .classicChrome, tags: ["Street Photography"]),
            recipe(name: "Bright Garden", filmSimulation: .velvia, tags: ["Landscape photography"])
        ])
        var filters = RecipeCatalog.Filters()
        filters.searchText = "CAFE street"

        XCTAssertEqual(catalog.recipes(matching: filters).map(\.name), ["Café Street"])
    }

    func testFiltersUseMappedMetadataAndSourceKeywords() {
        let catalog = RecipeCatalog(recipes: [
            recipe(
                name: "Night Walk",
                filmSimulation: .classicChrome,
                dynamicRange: .dr400,
                whiteBalance: .tungsten,
                tags: ["Night photography"]
            ),
            recipe(
                name: "Day Walk",
                filmSimulation: .velvia,
                dynamicRange: .dr100,
                whiteBalance: .daylight,
                tags: ["Travel photography"]
            )
        ])
        var filters = RecipeCatalog.Filters()
        filters.dynamicRange = .dr400
        filters.whiteBalance = .tungsten
        filters.keyword = "Night photography"

        XCTAssertEqual(catalog.recipes(matching: filters).map(\.name), ["Night Walk"])
        XCTAssertEqual(catalog.keywords.map(\.name), ["Night photography", "Travel photography"])
    }

    func testSortHasStableNameTieBreakers() {
        let catalog = RecipeCatalog(recipes: [
            recipe(name: "Zulu", filmSimulation: .velvia, date: "January 1, 2024"),
            recipe(name: "Alpha", filmSimulation: .velvia, date: "January 1, 2024"),
            recipe(name: "Middle", filmSimulation: .classicChrome, date: "January 1, 2025")
        ])
        var filters = RecipeCatalog.Filters()
        filters.sortOrder = .filmSimulation
        XCTAssertEqual(catalog.recipes(matching: filters).map(\.name), ["Middle", "Alpha", "Zulu"])

        filters.sortOrder = .newest
        XCTAssertEqual(catalog.recipes(matching: filters).map(\.name), ["Middle", "Alpha", "Zulu"])
    }

    func testLoaderPreservesSourceTagsAndDateWithoutChangingPresetMapping() {
        let json = RecipeJSON(
            id: "source-record",
            name: "Source Record",
            source: "Documented source",
            sensorGeneration: "X-Trans V",
            filmSimulation: "Classic Chrome",
            filmSimEnum: 11,
            settings: ["dynamicRange": "DR200"],
            ptpSettings: ["whiteBalance": 4],
            presetSettings: ["dynamicRange": 200, "filmSimulation": 11],
            sourceUrl: nil,
            previewImageUrl: nil,
            imageUrls: [],
            date: "March 27, 2024",
            compatibleCameras: ["X100VI"],
            tags: ["Travel photography"]
        )

        let recipe = RecipeLoader.recipe(from: json)

        XCTAssertEqual(recipe.source, "Documented source")
        XCTAssertEqual(recipe.tags, ["Travel photography"])
        XCTAssertEqual(recipe.date?.timeIntervalSince1970, 1_711_497_600)
        XCTAssertEqual(recipe.dynamicRange, .dr200)
        XCTAssertEqual(recipe.filmSimulation, .classicChrome)
    }

    private func recipe(
        name: String,
        filmSimulation: FilmSimulation,
        dynamicRange: DynamicRange = .dr100,
        whiteBalance: WhiteBalanceMode = .auto,
        tags: [String] = [],
        date: String? = nil
    ) -> Recipe {
        Recipe(
            id: name,
            name: name,
            source: "Test",
            sourceUrl: nil,
            date: date.flatMap(dateFormatter.date(from:)),
            dateString: date,
            filmSimulation: filmSimulation,
            dynamicRange: dynamicRange,
            whiteBalanceMode: whiteBalance,
            tags: tags
        )
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }
}
