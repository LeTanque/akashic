import AppKit
import XCTest
@testable import Akashic

final class AkashicScrollerGeometryTests: XCTestCase {
    func testGripLinesFitInsideKnob() {
        let knob = NSRect(x: 0, y: 10, width: AkashicScrollerGeometry.knobWidth, height: 80)
        let lines = AkashicScrollerGeometry.gripLineRects(in: knob)
        XCTAssertEqual(lines.count, AkashicScrollerGeometry.gripLineCount)
        for line in lines {
            XCTAssertTrue(knob.contains(line))
            XCTAssertEqual(line.height, AkashicScrollerGeometry.gripLineHeight)
        }
    }

    func testKnobRectStaysInsideSlot() {
        let slot = NSRect(x: 0, y: 0, width: 14, height: 200)
        let knob = AkashicScrollerGeometry.knobRect(in: slot, knobProportion: 0.25, knobProportionMin: 0.08)
        XCTAssertTrue(slot.contains(knob))
        XCTAssertEqual(knob.width, slot.width)
    }
}
