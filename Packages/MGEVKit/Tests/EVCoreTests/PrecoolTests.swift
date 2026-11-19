import Foundation
import MGKit
import OpenMeteo
import XCTest
@testable import EVCore

final class PrecoolTests: XCTestCase {
    let ist: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }()

    /// 2026-11-19 at `hour`:00 in India.
    func at(_ hour: Int) -> Date {
        ist.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: hour))!
    }

    func parked(climate: Bool = false, powerMode: Int = 0) -> VehicleSnapshot {
        VehicleSnapshot(
            statusTime: 0, socPercent: 60, rangeKm: 150, odometerKm: 1000, locked: true, driverDoorOpen: false,
            passengerDoorOpen: false, rearLeftDoorOpen: false, rearRightDoorOpen: false, bootOpen: false,
            bonnetOpen: false, anyWindowOpen: false, lightsOn: false, climateRunning: climate, interiorTempC: 27,
            exteriorTempC: 26, auxVolts: 12.6, tyres: nil, journeyId: 1, journeyDistanceRaw: 0, latitude: 12.97,
            longitude: 77.59, altitudeM: 900, gpsTime: nil, activeAlerts: [], powerMode: powerMode
        )
    }

    func weather(_ temp: Double, sun: Double = 800) -> Weather {
        Weather(tempC: temp, feelsLikeC: nil, sunWm2: sun, isDay: true, fetchedAt: Date())
    }

    func decide(
        enabled: Bool = true, threshold: Int = 29, snapshot: VehicleSnapshot? = nil, weather w: Weather?,
        last: Date? = nil, hour: Int = 14, sheltered: Bool = false
    ) -> Result<PrecoolAdvisor.Suggestion, PrecoolAdvisor.SkipReason> {
        PrecoolAdvisor.decide(
            enabled: enabled, thresholdC: threshold, snapshot: snapshot ?? parked(), weather: w, capacityKwh: 37.1,
            lastSuggestedAt: last, now: at(hour), calendar: ist, sheltered: sheltered
        )
    }

    func testAHotSunnyAfternoonSuggestsCooling() throws {
        let s = try decide(weather: weather(34, sun: 900)).get()
        XCTAssertEqual(44, s.cabinC, accuracy: 1e-9) // 34 °C air + 10 °C full-sun gain
        XCTAssertEqual(34, s.outsideC)
        XCTAssertEqual(15, s.minutes) // capped at 15
        XCTAssertEqual(2.0 * 15 / 60 / 37.1 * 100, s.batteryPercent, accuracy: 1e-9)
    }

    func testAMildDayStaysQuiet() {
        XCTAssertEqual(.failure(.init(.notHot)), decide(weather: weather(26, sun: 900)))
    }

    func testCoveredParkingGetsNoSunGain() {
        // 30 °C air in the shade: cabin 30, just over a 29 °C threshold.
        XCTAssertNoThrow(try decide(weather: weather(30, sun: 900), sheltered: true).get())
        XCTAssertEqual(.failure(.init(.notHot)), decide(threshold: 30, weather: weather(30, sun: 900), sheltered: true))
    }

    func testOnlyInDaytime() {
        XCTAssertEqual(.failure(.init(.night)), decide(weather: weather(34), hour: 6))
        XCTAssertEqual(.failure(.init(.night)), decide(weather: weather(34), hour: 19))
        XCTAssertNoThrow(try decide(weather: weather(34), hour: 7).get())
    }

    func testAtMostOneSuggestionEveryTwoHours() {
        XCTAssertEqual(.failure(.init(.coolingDown)), decide(weather: weather(34), last: at(13)))
        XCTAssertNoThrow(try decide(weather: weather(34), last: at(11)).get())
    }

    func testNotWhileTheCarIsOnOrAlreadyCooling() {
        XCTAssertEqual(.failure(.init(.carRunning)), decide(snapshot: parked(climate: true), weather: weather(34)))
        XCTAssertEqual(.failure(.init(.carRunning)), decide(snapshot: parked(powerMode: 2), weather: weather(34)))
    }

    func testNeedsWeatherAndCanBeTurnedOff() {
        XCTAssertEqual(.failure(.init(.noWeather)), decide(weather: nil))
        XCTAssertEqual(.failure(.init(.off)), decide(enabled: false, weather: weather(34)))
    }

    func testCabinUsesTheCarsSensorWhileItIsRunning() {
        let t = CabinModel.temps(parked(climate: true), weather: weather(34))
        XCTAssertEqual(27, t.cabinC)
        XCTAssertFalse(t.cabinEstimated)
        XCTAssertEqual(34, t.outsideC)
    }

    func testCoolingMinutesStayBetweenThreeAndFifteen() {
        XCTAssertEqual(3, Cooling.minutes(cabinC: 22))
        XCTAssertEqual(9, Cooling.minutes(cabinC: 34))
        XCTAssertEqual(15, Cooling.minutes(cabinC: 50))
    }
}
