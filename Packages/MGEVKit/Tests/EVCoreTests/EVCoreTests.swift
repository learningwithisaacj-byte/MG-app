import XCTest
import MGKit
@testable import EVCore

final class CarIdentityTests: XCTestCase {
    func identity(_ model: String?, _ series: String?) -> CarIdentity {
        CarIdentity.of(Vehicle(vin: "VIN", series: series, model: model, colorName: nil, isSubAccount: false))
    }

    func testKnownModelsMatchTheNameHoweverMgWordsIt() {
        XCTAssertEqual(.windsor, CarIdentity(name: "Windsor Pro").model)
        XCTAssertEqual(.comet, CarIdentity(name: "COMET EV EXCLUSIVE FC").model)
        XCTAssertEqual(.zsEv, CarIdentity(name: "ZS EV EXCLUSIVE").model)
        XCTAssertEqual(.m9, CarIdentity(name: "M9").model)
        XCTAssertEqual(.cyberster, CarIdentity(name: "Cyberster").model)
        XCTAssertEqual(.tomahawk, CarIdentity(name: "Hector Tomahawk EV").model)
    }

    func testTheTrimIsDroppedFromTheName() {
        XCTAssertEqual(CarIdentity(name: "Comet EV"), identity("COMET EV EXCLUSIVE FC", "E230"))
        XCTAssertEqual(CarIdentity(name: "Windsor"), identity("Windsor", "EQ100"))
    }

    func testASeriesCodeAloneIsEnough() {
        XCTAssertEqual(CarIdentity(name: "Comet EV"), identity(nil, "EC32"))
        XCTAssertEqual(CarIdentity(name: "Windsor"), identity(" ", "EQ100"))
    }

    func testAWindsorProNamedOnlyByItsTrim() {
        XCTAssertEqual(CarIdentity(name: "Windsor Pro"), identity("ESSENCE PRO", "EQ200"))
        XCTAssertEqual(CarIdentity(name: "Windsor Pro"), identity("Windsor Pro Essence", nil))
        XCTAssertEqual(CarIdentity(name: "Windsor Pro"), identity("Exclusive Pro", nil))
        XCTAssertEqual(CarIdentity(name: "Windsor"), identity("Essence", nil))
        XCTAssertEqual(CarIdentity(name: "Windsor"), identity("EXCLUSIVE", "EQ100"))
    }

    func testTrimsOnlyOneModelSellsNameIt() {
        XCTAssertEqual(CarIdentity(name: "ZS EV"), identity("EXCITE PRO", nil))
        XCTAssertEqual(CarIdentity(name: "ZS EV"), identity("Exclusive Plus", nil))
        XCTAssertEqual(CarIdentity(name: "Comet EV"), identity("EXCITE FC", nil))
        XCTAssertEqual(CarIdentity(name: "Comet EV"), identity("Exclusive FC", nil))
        XCTAssertEqual(CarIdentity(name: "Comet EV"), identity("PLUSH", nil))
    }

    func testTrimsSeveralModelsSellKeepMgsName() {
        XCTAssertEqual(CarIdentity(name: "EXECUTIVE"), identity("EXECUTIVE", nil))
        XCTAssertEqual(CarIdentity(name: "Excite"), identity("Excite", nil))
        XCTAssertEqual(CarIdentity(name: "Exclusive"), identity("Exclusive", nil))
    }

    func testPetrolMgsWithProTrimsAreNotEvs() {
        XCTAssertEqual(.other, identity("HECTOR SHARP PRO", nil).model)
        XCTAssertEqual(.other, identity("ASTOR SAVVY PRO", nil).model)
    }

    func testAnotherModelsEssenceTrimStaysThatModel() {
        XCTAssertEqual(CarIdentity(name: "ZS EV"), identity("ZS EV ESSENCE", nil))
    }

    func testNoModelIsUnknown() {
        XCTAssertEqual(.unknown, identity(nil, nil))
        XCTAssertEqual(.unknown, CarIdentity.of(nil))
    }
}

final class VehicleProfileTests: XCTestCase {
    func testRangeUsesUsableEnergyAboveTheReserve() {
        let p = VehicleProfile()
        XCTAssertEqual(37.1 * 0.5 * 7, p.cityRangeKm(50), accuracy: 1e-9)
        XCTAssertEqual((37.1 * 0.5 - 37.1 * 0.1) * 6, p.rangeKm(50, kmPerKwh: 6, reservePercent: 10), accuracy: 1e-9)
        XCTAssertEqual(0, p.rangeKm(5, kmPerKwh: 6, reservePercent: 10))
    }

    func testDefaultsAreValidAndBadValuesAreNamed() {
        XCTAssertEqual([], VehicleProfile().validate())
        var p = VehicleProfile()
        p.usableCapacityKwh = 5
        p.dcCurve = [.init(10, 40)]
        XCTAssertEqual(2, p.validate().count)
    }

    func testStartingProfileUsesTheSoldPack() {
        XCTAssertEqual(17.3, VehicleProfile.starting(for: .comet).usableCapacityKwh)
        XCTAssertEqual(37.1, VehicleProfile.starting(for: .windsor).usableCapacityKwh)
    }

    func testCapacityIsLearnedFromTheMedianOfGoodReadings() {
        XCTAssertEqual(37.1, try XCTUnwrap(CapacityLearning.sample(socPercent: 59, energyKwh: 21.9)), accuracy: 0.05)
        XCTAssertNil(CapacityLearning.sample(socPercent: 15, energyKwh: 5))
        XCTAssertNil(CapacityLearning.sample(socPercent: 50, energyKwh: nil))
        var samples: [Double] = []
        for s in [52.0, 51.8, 80.0] { samples = CapacityLearning.append(samples, s) }
        XCTAssertEqual(52.0, CapacityLearning.learned(samples))
        XCTAssertNil(CapacityLearning.learned([52]))
        XCTAssertTrue(CapacityLearning.shouldReplace(current: 37.1, learned: 52))
        XCTAssertFalse(CapacityLearning.shouldReplace(current: 37.1, learned: 37.3))
    }
}
