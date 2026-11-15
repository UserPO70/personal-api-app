import XCTest
import UIKit
@testable import PersonalAPI

final class DesignTests: XCTestCase {
    private func farbe(_ name: Farbe, dunkel: Bool, kontrast: Bool = false) throws -> [Int] {
        let farbe = try XCTUnwrap(UIColor(named: name.rawValue, in: Bundle.main, compatibleWith: nil),
                                  "Farbsatz \(name.rawValue) fehlt")
        let merkmale = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: dunkel ? .dark : .light),
            UITraitCollection(accessibilityContrast: kontrast ? .high : .normal),
        ])
        var rot: CGFloat = 0, gruen: CGFloat = 0, blau: CGFloat = 0, deckung: CGFloat = 0
        farbe.resolvedColor(with: merkmale).getRed(&rot, green: &gruen, blue: &blau, alpha: &deckung)
        return [rot, gruen, blau].map { Int(($0 * 255).rounded()) }
    }

    /// Ein Tippfehler im Namen ergäbe sonst still eine durchsichtige Farbe.
    func testJederFarbsatzIstDa() throws {
        for name in Farbe.allCases {
            _ = try farbe(name, dunkel: false)
        }
    }

    func testHellUndDunkelWieImDesignkonzept() throws {
        XCTAssertEqual(try farbe(.grund, dunkel: false), [0xEE, 0xF2, 0xF2])
        XCTAssertEqual(try farbe(.grund, dunkel: true), [0x0B, 0x12, 0x13])
        XCTAssertEqual(try farbe(.essen, dunkel: false), [0xE0, 0x5A, 0x03])
        XCTAssertEqual(try farbe(.fehler, dunkel: true), [0xFF, 0x8A, 0x80])
    }

    /// Mit „Kontrast erhöhen“ wird gedämpfter Text so kräftig wie normaler Text.
    func testErhoehterKontrast() throws {
        XCTAssertEqual(try farbe(.text2, dunkel: false, kontrast: true), try farbe(.text, dunkel: false))
        XCTAssertEqual(try farbe(.text3, dunkel: true, kontrast: true), try farbe(.text, dunkel: true))
        XCTAssertEqual(try farbe(.rand, dunkel: false, kontrast: true), try farbe(.text3, dunkel: false))
    }
}
