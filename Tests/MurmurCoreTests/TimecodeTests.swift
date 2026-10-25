import XCTest
@testable import MurmurCore

final class TimecodeTests: XCTestCase {
    func testMinutesAndSeconds() {
        XCTAssertEqual(Timecode.format(0), "00:00")
        XCTAssertEqual(Timecode.format(65), "01:05")
        XCTAssertEqual(Timecode.format(599), "09:59")
    }

    func testHoursSwitchFormat() {
        XCTAssertEqual(Timecode.format(3600), "1:00:00")
        XCTAssertEqual(Timecode.format(3725), "1:02:05")
    }

    func testBadInputClampsToZero() {
        XCTAssertEqual(Timecode.format(-5), "00:00")
        XCTAssertEqual(Timecode.format(.nan), "00:00")
        XCTAssertEqual(Timecode.format(.infinity), "00:00")
    }
}
