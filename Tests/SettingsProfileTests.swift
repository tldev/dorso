import XCTest
import AppKit
@testable import PosturrCore

final class SettingsProfileTests: XCTestCase {

    func testEncodedColorDataRoundTrip() {
        let original = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        let data = SettingsProfile.encodedColorData(from: original)

        let profile = SettingsProfile(
            id: "test",
            name: "Test",
            warningMode: .blur,
            warningColorData: data,
            deadZone: 0.03,
            intensity: 1.0,
            warningOnsetDelay: 0,
            detectionMode: .balanced
        )

        let decoded = profile.warningColor
        let originalRGB = original.usingColorSpace(.sRGB) ?? original
        let decodedRGB = decoded.usingColorSpace(.sRGB) ?? decoded

        var r0: CGFloat = 0
        var g0: CGFloat = 0
        var b0: CGFloat = 0
        var a0: CGFloat = 0
        originalRGB.getRed(&r0, green: &g0, blue: &b0, alpha: &a0)

        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        decodedRGB.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)

        XCTAssertEqual(Double(a1), Double(a0), accuracy: 0.001)
        XCTAssertLessThanOrEqual(abs(Double(r1 - r0)), 0.1)
        XCTAssertLessThanOrEqual(abs(Double(g1 - g0)), 0.1)
        XCTAssertLessThanOrEqual(abs(Double(b1 - b0)), 0.1)
    }

    func testLegacyColorDataStillDecodes() throws {
        let original = NSColor(srgbRed: 0.9, green: 0.8, blue: 0.1, alpha: 1.0)
        let legacyData = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: false)

        let profile = SettingsProfile(
            id: "legacy",
            name: "Legacy",
            warningMode: .blur,
            warningColorData: legacyData,
            deadZone: 0.03,
            intensity: 1.0,
            warningOnsetDelay: 0,
            detectionMode: .balanced
        )

        let decoded = profile.warningColor
        let originalRGB = original.usingColorSpace(.sRGB) ?? original
        let decodedRGB = decoded.usingColorSpace(.sRGB) ?? decoded

        var r0: CGFloat = 0
        var g0: CGFloat = 0
        var b0: CGFloat = 0
        var a0: CGFloat = 0
        originalRGB.getRed(&r0, green: &g0, blue: &b0, alpha: &a0)

        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        decodedRGB.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)

        XCTAssertEqual(Double(a1), Double(a0), accuracy: 0.001)
        XCTAssertLessThanOrEqual(abs(Double(r1 - r0)), 0.1)
        XCTAssertLessThanOrEqual(abs(Double(g1 - g0)), 0.1)
        XCTAssertLessThanOrEqual(abs(Double(b1 - b0)), 0.1)
    }
}
