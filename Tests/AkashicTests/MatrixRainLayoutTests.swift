import CoreGraphics
@testable import Akashic
import XCTest

final class MatrixRainLayoutTests: XCTestCase {
    func testGridDimensionsFromSize() {
        let layout = MatrixRainLayout(size: CGSize(width: 820, height: 520))
        XCTAssertEqual(layout.columns, max(1, Int(820 / MatrixRainStyle.columnWidth)))
        XCTAssertEqual(layout.rows, max(1, Int(520 / MatrixRainStyle.rowHeight)))
    }

    func testMatchesSizeExactly() {
        let size = CGSize(width: 400, height: 300)
        let layout = MatrixRainLayout(size: size)
        XCTAssertTrue(layout.matches(size: size))
        XCTAssertFalse(layout.matches(size: CGSize(width: 401, height: 300)))
    }

    func testTrailIntensityPeaksAtHeadAndDecays() {
        let layout = MatrixRainLayout(size: CGSize(width: 200, height: 200))
        XCTAssertEqual(layout.trailIntensity(delta: 0), 1, accuracy: 0.0001)
        XCTAssertGreaterThan(layout.trailIntensity(delta: 1), layout.trailIntensity(delta: 5))
        XCTAssertEqual(layout.trailIntensity(delta: MatrixRainStyle.trailLength), 0, accuracy: 0.0001)
        XCTAssertEqual(layout.trailIntensity(delta: -1), 0, accuracy: 0.0001)
    }

    func testHeadRowStaysWithinCycle() {
        let layout = MatrixRainLayout(size: CGSize(width: 320, height: 240))
        let cycle = Double(layout.rows) + MatrixRainStyle.trailLength
        for column in 0 ..< min(layout.columns, 8) {
            for time in [0.0, 0.5, 2.0, 17.0, 400.0] {
                let head = layout.headRow(forColumn: column, time: time)
                XCTAssertGreaterThanOrEqual(head, 0)
                XCTAssertLessThan(head, cycle)
            }
        }
    }

    func testGlyphIndicesStayInPoolRange() {
        let layout = MatrixRainLayout(size: CGSize(width: 640, height: 480))
        let poolCount = MatrixRainStyle.glyphPool.count
        for column in 0 ..< layout.columns {
            for row in 0 ..< layout.rows {
                let index = layout.glyphIndex(column: column, row: row)
                XCTAssertGreaterThanOrEqual(index, 0)
                XCTAssertLessThan(index, poolCount)
            }
        }
    }
}
