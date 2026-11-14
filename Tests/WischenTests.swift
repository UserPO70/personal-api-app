import XCTest
@testable import PersonalAPI

final class WischenTests: XCTestCase {
    func testNachLinksGehtZumNaechstenTab() {
        XCTAssertEqual(Wischen.richtung(waagerecht: -120, senkrecht: 10), 1)
        XCTAssertEqual(Wischen.richtung(waagerecht: 120, senkrecht: -10), -1)
    }

    func testScrollenUndKurzeBewegungenWechselnNichts() {
        XCTAssertEqual(Wischen.richtung(waagerecht: -40, senkrecht: 0), 0)      // zu kurz
        XCTAssertEqual(Wischen.richtung(waagerecht: -120, senkrecht: 100), 0)   // schräg: eher Scrollen
        XCTAssertEqual(Wischen.richtung(waagerecht: 5, senkrecht: 300), 0)      // Scrollen
        XCTAssertEqual(Wischen.richtung(waagerecht: -70, senkrecht: 28), 1)     // gerade noch waagerecht genug
        XCTAssertEqual(Wischen.richtung(waagerecht: -70, senkrecht: 29), 0)
    }

    func testAmRandBleibtEsBeimErstenUndLetztenTab() {
        XCTAssertEqual(Wischen.ziel(aktuell: 0, richtung: 1, anzahl: 3), 1)
        XCTAssertEqual(Wischen.ziel(aktuell: 1, richtung: 1, anzahl: 3), 2)
        XCTAssertEqual(Wischen.ziel(aktuell: 2, richtung: 1, anzahl: 3), 2)
        XCTAssertEqual(Wischen.ziel(aktuell: 0, richtung: -1, anzahl: 3), 0)
        XCTAssertEqual(Wischen.ziel(aktuell: 2, richtung: -1, anzahl: 3), 1)
    }
}
