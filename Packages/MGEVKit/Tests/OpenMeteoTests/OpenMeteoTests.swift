import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import OpenMeteo

/// A reply shaped like Open-Meteo's for `current=temperature_2m,apparent_temperature,shortwave_radiation,is_day`.
let sampleReply = """
{"latitude":12.98,"longitude":77.6,"generationtime_ms":0.03,"utc_offset_seconds":0,"timezone":"GMT","elevation":920.0,
"current_units":{"time":"iso8601","interval":"seconds","temperature_2m":"°C","apparent_temperature":"°C","shortwave_radiation":"W/m²","is_day":""},
"current":{"time":"2026-11-19T06:15","interval":900,"temperature_2m":33.4,"apparent_temperature":36.1,"shortwave_radiation":812.0,"is_day":1}}
"""

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    private(set) var lastURL: URL?
    func hit(_ url: URL?) { lock.lock(); n += 1; lastURL = url; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}

final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_795_000_000)
}

final class OpenMeteoTests: XCTestCase {
    func testDecodesTheCurrentWeather() throws {
        let at = Date(timeIntervalSince1970: 1)
        let w = try OpenMeteoClient.decode(Data(sampleReply.utf8), fetchedAt: at)
        XCTAssertEqual(Weather(tempC: 33.4, feelsLikeC: 36.1, sunWm2: 812, isDay: true, fetchedAt: at), w)
    }

    func testMissingOptionalFieldsHaveSafeDefaults() throws {
        let w = try OpenMeteoClient.decode(Data(#"{"current":{"temperature_2m":21.5}}"#.utf8), fetchedAt: Date())
        XCTAssertEqual(21.5, w.tempC)
        XCTAssertNil(w.feelsLikeC)
        XCTAssertEqual(0, w.sunWm2)
        XCTAssertTrue(w.isDay)
    }

    func testAnErrorBodyIsUnreadable() {
        XCTAssertThrowsError(try OpenMeteoClient.decode(Data(#"{"error":true,"reason":"bad"}"#.utf8), fetchedAt: Date())) {
            XCTAssertEqual(WeatherError.unreadable, $0 as? WeatherError)
        }
    }

    func testAsksForTheRightFieldsWithNoKey() async throws {
        let calls = Counter()
        let client = OpenMeteoClient(fetch: { req in calls.hit(req.url); return (Data(sampleReply.utf8), 200) })
        _ = try await client.current(latitude: 12.971599, longitude: 77.594566)
        let url = try XCTUnwrap(calls.lastURL?.absoluteString)
        XCTAssertTrue(url.hasPrefix("https://api.open-meteo.com/v1/forecast?"))
        XCTAssertTrue(url.contains("latitude=12.9716"))
        XCTAssertTrue(url.contains("longitude=77.5946"))
        XCTAssertTrue(url.contains("current=temperature_2m,apparent_temperature,shortwave_radiation,is_day"))
        XCTAssertFalse(url.lowercased().contains("apikey"))
    }

    func testCachesFifteenMinutesPerSquare() async throws {
        let calls = Counter()
        let clock = Clock()
        let client = OpenMeteoClient(now: { clock.now }, fetch: { req in calls.hit(req.url); return (Data(sampleReply.utf8), 200) })
        _ = try await client.current(latitude: 12.9716, longitude: 77.5946)
        _ = try await client.current(latitude: 12.9719, longitude: 77.5941) // same ~1 km square
        XCTAssertEqual(1, calls.count)
        _ = try await client.current(latitude: 13.10, longitude: 77.59) // another square
        XCTAssertEqual(2, calls.count)
        clock.now = clock.now.addingTimeInterval(16 * 60)
        _ = try await client.current(latitude: 12.9716, longitude: 77.5946)
        XCTAssertEqual(3, calls.count)
    }

    func testHttpErrorsAreReportedAndNotCached() async throws {
        let calls = Counter()
        let client = OpenMeteoClient(fetch: { req in calls.hit(req.url); return (Data(), 429) })
        do {
            _ = try await client.current(latitude: 1, longitude: 2)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(WeatherError.http(429), error as? WeatherError)
        }
        _ = try? await client.current(latitude: 1, longitude: 2)
        XCTAssertEqual(2, calls.count)
    }
}
