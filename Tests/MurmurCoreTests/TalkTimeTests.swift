import XCTest
@testable import MurmurCore

final class TalkTimeTests: XCTestCase {
    func testSharesAddUpAndSortLongestFirst() {
        let segments = [
            TranscriptSegment(start: 0, end: 10, text: "a", speakerIndex: 0),
            TranscriptSegment(start: 10, end: 40, text: "b", speakerIndex: 1),
            TranscriptSegment(start: 40, end: 50, text: "c", speakerIndex: 0),
        ]
        let shares = TalkTime.shares(segments: segments, names: ["Alex", "Priya"])
        XCTAssertEqual(shares.map(\.name), ["Priya", "Alex"])
        XCTAssertEqual(shares.map(\.percent), [60, 40])
        XCTAssertEqual(shares.map(\.fraction).reduce(0, +), 1, accuracy: 0.0001)
    }

    func testUnnamedSpeakersGetDefaultNames() {
        let segments = [TranscriptSegment(start: 0, end: 5, text: "a", speakerIndex: 2)]
        XCTAssertEqual(TalkTime.shares(segments: segments, names: []).first?.name, "Speaker 3")
    }

    func testNoSpeakersGivesNoShares() {
        let segments = [TranscriptSegment(start: 0, end: 5, text: "a", speakerIndex: nil)]
        XCTAssertTrue(TalkTime.shares(segments: segments, names: []).isEmpty)
        XCTAssertTrue(TalkTime.shares(segments: [], names: []).isEmpty)
    }
}
