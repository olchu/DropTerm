import CoreGraphics
import Testing
@testable import DropTerm

@Suite("Panel layout")
struct PanelLayoutTests {
    @Test("Panel occupies forty percent of the visible display")
    func visibleFrame() {
        let screen = CGRect(x: 100, y: 0, width: 1_440, height: 950)
        let visible = CGRect(x: 100, y: 50, width: 1_440, height: 900)
        let frames = PanelLayout().frames(screenFrame: screen, visibleFrame: visible)

        #expect(frames.visible == CGRect(x: 100, y: 0, width: 1_440, height: 420))
    }

    @Test("Hidden panel is entirely below the visible display")
    func hiddenFrame() {
        let screen = CGRect(x: 0, y: 0, width: 1_200, height: 825)
        let visible = CGRect(x: 0, y: 25, width: 1_200, height: 800)
        let frames = PanelLayout().frames(screenFrame: screen, visibleFrame: visible)

        #expect(frames.hidden.maxY < screen.minY)
    }
}
