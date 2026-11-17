import AppKit
import Testing
import ErgoCore
@testable import ErgoLauncher

@Suite struct GeometryTests {
    let vf = NSRect(x: 0, y: 0, width: 1600, height: 900)

    @Test func defaultPlacementIsCenteredNearTop() {
        let size = NSSize(width: 720, height: 60)
        let o = LauncherGeometry.origin(placement: nil, size: size, visibleFrame: vf)
        #expect(abs(o.x + size.width / 2 - vf.midX) < 0.5)
        #expect(abs((o.y + size.height) - (vf.maxY - vf.height * 0.22)) < 0.5)
    }

    @Test func placementRoundTrip() {
        let size = NSSize(width: 720, height: 60)
        let frame = NSRect(x: 300, y: 500, width: size.width, height: size.height)
        let p = LauncherGeometry.placement(for: frame, screenUUID: "A", visibleFrame: vf)
        let o = LauncherGeometry.origin(placement: p, size: size, visibleFrame: vf)
        #expect(abs(o.x - frame.origin.x) < 0.5)
        #expect(abs(o.y - frame.origin.y) < 0.5)
    }

    @Test func placementScalesToOtherScreen() {
        let size = NSSize(width: 600, height: 60)
        let p = LauncherPlacement(screenUUID: "A", centerXRatio: 0.25, topOffset: 100)
        let other = NSRect(x: 1600, y: 0, width: 2560, height: 1400)
        let o = LauncherGeometry.origin(placement: p, size: size, visibleFrame: other)
        #expect(abs(o.x + 300 - (1600 + 0.25 * 2560)) < 0.5)
        #expect(abs(o.y + 60 - (1400 - 100)) < 0.5)
    }

    @Test func clampKeepsInsideScreen() {
        let size = NSSize(width: 720, height: 400)
        let p = LauncherPlacement(screenUUID: "A", centerXRatio: 0.99, topOffset: 880)
        let o = LauncherGeometry.origin(placement: p, size: size, visibleFrame: vf)
        #expect(o.x + size.width <= vf.maxX + 0.5)
        #expect(o.y >= vf.minY)
    }

    @Test func resizeKeepsTopAndCenter() {
        let old = NSRect(x: 400, y: 700, width: 720, height: 60)
        let r = LauncherGeometry.resized(old: old, newSize: NSSize(width: 720, height: 400), visibleFrame: vf)
        #expect(r.maxY == old.maxY)
        #expect(r.midX == old.midX)
    }
}
