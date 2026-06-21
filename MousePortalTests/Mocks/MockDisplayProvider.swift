import Foundation
import CoreGraphics
@testable import MousePortal

final class MockDisplayProvider: DisplayProviding {
    var mockDisplays: [DisplayInfo] = []
    var mockBounds: [CGDirectDisplayID: CGRect] = [:]
    var mockMainDisplayID: CGDirectDisplayID = 1

    func getActiveDisplays() -> [DisplayInfo] {
        return mockDisplays
    }

    func getDisplayBounds(displayID: CGDirectDisplayID) -> CGRect {
        return mockBounds[displayID] ?? .zero
    }

    func getMainDisplayID() -> CGDirectDisplayID {
        return mockMainDisplayID
    }

    // MARK: - Test Helpers

    /// 设置双显示器左右排列
    func setupDualDisplayHorizontal() {
        let mainDisplay = DisplayInfo(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            isMain: true,
            name: "Main Display"
        )
        let externalDisplay = DisplayInfo(
            id: 2,
            frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            isMain: false,
            name: "External Display"
        )
        mockDisplays = [mainDisplay, externalDisplay]
        mockBounds = [1: mainDisplay.frame, 2: externalDisplay.frame]
        mockMainDisplayID = 1
    }

    /// 设置双显示器上下排列
    func setupDualDisplayVertical() {
        let mainDisplay = DisplayInfo(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            isMain: true,
            name: "Main Display"
        )
        let externalDisplay = DisplayInfo(
            id: 2,
            frame: CGRect(x: 0, y: 1080, width: 1920, height: 1080),
            isMain: false,
            name: "External Display"
        )
        mockDisplays = [mainDisplay, externalDisplay]
        mockBounds = [1: mainDisplay.frame, 2: externalDisplay.frame]
        mockMainDisplayID = 1
    }

    /// 设置单显示器
    func setupSingleDisplay() {
        let display = DisplayInfo(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            isMain: true,
            name: "Main Display"
        )
        mockDisplays = [display]
        mockBounds = [1: display.frame]
        mockMainDisplayID = 1
    }
}
