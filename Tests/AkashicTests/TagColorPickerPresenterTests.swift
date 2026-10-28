import AppKit
import XCTest
@testable import Akashic

@MainActor
final class TagColorPickerPresenterTests: XCTestCase {
    func testPanelOriginClampsWithinVisibleFrame() {
        let anchor = NSRect(x: 100, y: 200, width: 80, height: 24)
        let panelSize = TagColorPickerPresenter.defaultPanelSize
        let visible = NSRect(x: 0, y: 0, width: 800, height: 600)
        let origin = TagColorPickerPresenter.panelOrigin(anchorOnScreen: anchor, panelSize: panelSize)
        XCTAssertGreaterThanOrEqual(origin.x, visible.minX + 8)
        XCTAssertLessThanOrEqual(origin.x + panelSize.width, visible.maxX - 8)
        XCTAssertGreaterThanOrEqual(origin.y, visible.minY + 8)
        XCTAssertEqual(origin.x, anchor.midX - panelSize.width / 2, accuracy: 0.5)
        XCTAssertEqual(origin.y, anchor.minY - panelSize.height - 8, accuracy: 0.5)
    }

    func testPresenterSeamReturnsInjectedChoice() {
        let tag = AkashicTag(name: "work", color: .cyan)
        let anchor = NSRect(x: 0, y: 0, width: 40, height: 20)
        struct Stub: TagColorPickerPresenting {
            let color: AkashicTagColor?
            func pickColor(for tag: AkashicTag, anchorOnScreen: NSRect) -> AkashicTagColor? { color }
        }
        XCTAssertEqual(Stub(color: .orange).pickColor(for: tag, anchorOnScreen: anchor), .orange)
        XCTAssertNil(Stub(color: nil).pickColor(for: tag, anchorOnScreen: anchor))
    }
}
