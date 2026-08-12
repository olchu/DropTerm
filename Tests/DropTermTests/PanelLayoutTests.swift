import CoreGraphics
import Testing
@testable import DropTerm

@Suite("Panel layout")
struct PanelLayoutTests {
    @Test("Panel occupies forty percent of the visible display")
    func visibleFrame() {
        let display = CGRect(x: 100, y: 50, width: 1_440, height: 900)
        let frames = PanelLayout().frames(in: display)

        #expect(frames.visible == CGRect(x: 100, y: 50, width: 1_440, height: 360))
    }

    @Test("Hidden panel is entirely below the visible display")
    func hiddenFrame() {
        let display = CGRect(x: 0, y: 25, width: 1_200, height: 800)
        let frames = PanelLayout().frames(in: display)

        #expect(frames.hidden.maxY < display.minY)
    }
}

