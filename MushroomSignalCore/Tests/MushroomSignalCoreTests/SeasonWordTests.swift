import XCTest
@testable import MushroomSignalCore

final class SeasonWordTests: XCTestCase {
    func testAllTwelveMonthsResolveToOneOfFourWords() {
        let validWords: Set<String> = ["jar", "leto", "jeseň", "zima"]
        for month in 1...12 {
            XCTAssertTrue(validWords.contains(SeasonWord.forMonth(month)), "month \(month) resolved to an unexpected word")
        }
    }

    func testDecemberJanuaryFebruaryAreWinter() {
        XCTAssertEqual(SeasonWord.forMonth(12), "zima")
        XCTAssertEqual(SeasonWord.forMonth(1), "zima")
        XCTAssertEqual(SeasonWord.forMonth(2), "zima")
    }

    func testMarchAprilMayAreSpring() {
        XCTAssertEqual(SeasonWord.forMonth(3), "jar")
        XCTAssertEqual(SeasonWord.forMonth(4), "jar")
        XCTAssertEqual(SeasonWord.forMonth(5), "jar")
    }

    func testJuneJulyAugustAreSummer() {
        XCTAssertEqual(SeasonWord.forMonth(6), "leto")
        XCTAssertEqual(SeasonWord.forMonth(7), "leto")
        XCTAssertEqual(SeasonWord.forMonth(8), "leto")
    }

    func testSeptemberOctoberNovemberAreAutumn() {
        XCTAssertEqual(SeasonWord.forMonth(9), "jeseň")
        XCTAssertEqual(SeasonWord.forMonth(10), "jeseň")
        XCTAssertEqual(SeasonWord.forMonth(11), "jeseň")
    }
}
