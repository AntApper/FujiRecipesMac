import XCTest
@testable import FujiRecipesCore

final class GridNavigationTests: XCTestCase {
    func testColumnCountMatchesTheRecipeGridAtCommonWidths() {
        XCTAssertEqual(GridNavigation.columnCount(width: 548, minimum: 330, spacing: 14), 1)
        XCTAssertEqual(GridNavigation.columnCount(width: 674, minimum: 330, spacing: 14), 2)
        XCTAssertEqual(GridNavigation.columnCount(width: 828, minimum: 330, spacing: 14), 2)
        XCTAssertEqual(GridNavigation.columnCount(width: 1018, minimum: 330, spacing: 14), 3)
    }

    func testColumnCountNeverDropsBelowOne() {
        XCTAssertEqual(GridNavigation.columnCount(width: 0, minimum: 330, spacing: 14), 1)
        XCTAssertEqual(GridNavigation.columnCount(width: 120, minimum: 330, spacing: 14), 1)
    }

    func testUpAndDownMoveByOneRowInATwoColumnGrid() {
        XCTAssertEqual(GridNavigation.index(from: 0, move: .down, count: 50, columns: 2), 2)
        XCTAssertEqual(GridNavigation.index(from: 3, move: .up, count: 50, columns: 2), 1)
        XCTAssertEqual(GridNavigation.index(from: 7, move: .down, count: 50, columns: 3), 10)
    }

    func testLeftAndRightFollowReadingOrderAcrossRows() {
        XCTAssertEqual(GridNavigation.index(from: 1, move: .right, count: 50, columns: 2), 2)
        XCTAssertEqual(GridNavigation.index(from: 2, move: .left, count: 50, columns: 2), 1)
    }

    func testMovesStopAtTheGridEdges() {
        XCTAssertEqual(GridNavigation.index(from: 0, move: .left, count: 5, columns: 2), 0)
        XCTAssertEqual(GridNavigation.index(from: 1, move: .up, count: 5, columns: 2), 1)
        XCTAssertEqual(GridNavigation.index(from: 4, move: .right, count: 5, columns: 2), 4)
        XCTAssertEqual(GridNavigation.index(from: 4, move: .down, count: 5, columns: 2), 4)
    }

    func testDownIntoAShorterLastRowLandsOnItsLastItem() {
        XCTAssertEqual(GridNavigation.index(from: 3, move: .down, count: 5, columns: 2), 4)
        XCTAssertEqual(GridNavigation.index(from: 5, move: .down, count: 7, columns: 3), 6)
    }

    func testDownInTheLastRowStaysPut() {
        XCTAssertEqual(GridNavigation.index(from: 6, move: .down, count: 7, columns: 3), 6)
    }
}
