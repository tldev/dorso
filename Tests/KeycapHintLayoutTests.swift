import XCTest

@testable import DorsoCore

final class KeycapHintLayoutTests: XCTestCase {
    func testEnglishHintKeepsLogicalOrder() {
        let text = "Press {Space} while looking at the ring"
        XCTAssertEqual(KeycapHintLayout.direction(of: text), .leftToRight)
        assertSegments(
            KeycapHintLayout.visualSegments(in: text),
            [
                (text: "Press ", isKeycap: false),
                (text: "Space", isKeycap: true),
                (text: " while looking at the ring", isKeycap: false),
            ]
        )
    }

    func testPersianHintIsRightToLeftAndReversed() {
        let text = "در حالی که به حلقه نگاه می‌کنید، {Space} را فشار دهید"
        XCTAssertEqual(KeycapHintLayout.direction(of: text), .rightToLeft)
        assertSegments(
            KeycapHintLayout.visualSegments(in: text),
            [
                (text: " را فشار دهید", isKeycap: false),
                (text: "Space", isKeycap: true),
                (text: "در حالی که به حلقه نگاه می‌کنید، ", isKeycap: false),
            ]
        )
    }

    /// Reading the visual line from its right edge recovers move, then select, then cancel.
    func testPersianDeskKeysHintVisualOrder() {
        let text = "جابه‌جایی با {↑}{↓}   انتخاب با {↩}   لغو با {Esc}"
        XCTAssertEqual(KeycapHintLayout.direction(of: text), .rightToLeft)
        let readingOrder = Array(KeycapHintLayout.visualSegments(in: text).reversed())
        XCTAssertEqual(
            readingOrder.map(\.text),
            [
                "جابه‌جایی با ",
                "↑",
                "↓",
                "   انتخاب با ",
                "↩",
                "   لغو با ",
                "Esc",
            ]
        )
        XCTAssertEqual(readingOrder.map(\.isKeycap), [false, true, true, false, true, false, true])
    }

    func testKeycapsAndStringsWithoutStrongLettersStayLeftToRight() {
        XCTAssertEqual(KeycapHintLayout.direction(of: "{Space}{Esc}"), .leftToRight)
        assertSegments(
            KeycapHintLayout.visualSegments(in: "{↑}{↓}{Esc}"),
            [
                (text: "↑", isKeycap: true),
                (text: "↓", isKeycap: true),
                (text: "Esc", isKeycap: true),
            ]
        )

        let digitsAndPunctuation = "12 {N} !!"
        XCTAssertEqual(KeycapHintLayout.direction(of: digitsAndPunctuation), .leftToRight)
        assertSegments(
            KeycapHintLayout.visualSegments(in: digitsAndPunctuation),
            [
                (text: "12 ", isKeycap: false),
                (text: "N", isKeycap: true),
                (text: " !!", isKeycap: false),
            ]
        )
    }

    func testPersianBeforeALatinNameStaysRightToLeft() {
        let text = "برای Dorso {Esc} را بزنید"
        XCTAssertEqual(KeycapHintLayout.direction(of: text), .rightToLeft)
        assertSegments(
            KeycapHintLayout.visualSegments(in: text),
            [
                (text: " را بزنید", isKeycap: false),
                (text: "Esc", isKeycap: true),
                (text: "برای Dorso ", isKeycap: false),
            ]
        )
    }

    func testLatinBeforePersianStaysLeftToRight() {
        let text = "Dorso {Esc} را بزنید"
        XCTAssertEqual(KeycapHintLayout.direction(of: text), .leftToRight)
        assertSegments(
            KeycapHintLayout.visualSegments(in: text),
            [
                (text: "Dorso ", isKeycap: false),
                (text: "Esc", isKeycap: true),
                (text: " را بزنید", isKeycap: false),
            ]
        )
    }

    func testHebrewIsRightToLeft() {
        let text = "עזרה {Esc}"
        XCTAssertEqual(KeycapHintLayout.direction(of: text), .rightToLeft)
        assertSegments(
            KeycapHintLayout.visualSegments(in: text),
            [
                (text: "Esc", isKeycap: true),
                (text: "עזרה ", isKeycap: false),
            ]
        )
    }

    /// Labeled tuples are not Equatable on this toolchain, so compare the fields.
    private func assertSegments(
        _ actual: [(text: String, isKeycap: Bool)],
        _ expected: [(text: String, isKeycap: Bool)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.map(\.text), expected.map(\.text), file: file, line: line)
        XCTAssertEqual(actual.map(\.isKeycap), expected.map(\.isKeycap), file: file, line: line)
    }
}
