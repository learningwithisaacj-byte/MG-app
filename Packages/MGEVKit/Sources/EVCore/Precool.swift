// Decision rules follow Volta's smart pre-cool (Apache 2.0, https://github.com/irshadm/volta-android). See NOTICE.md.

import Foundation
import MGKit
import OpenMeteo

/// Works out the cabin temperature of a parked car. The car's own sensors are live only while it is on; once
/// parked, a closed cabin heads for the air temperature plus the sun's heating.
public enum CabinModel {
    /// How much hotter than the air a closed cabin gets in full sun (about 900 W/m²). Kept modest: the car is often
    /// under a roof or a tree, and an over-warm guess makes the AC look needed when it isn't.
    public static let fullSunGainC = 10.0

    public struct Temps: Equatable, Sendable {
        public let outsideC: Double?
        public let cabinC: Double?
        /// The cabin figure is worked out from the weather, not measured by the car.
        public let cabinEstimated: Bool
    }

    public static func temps(_ snapshot: VehicleSnapshot?, weather: Weather?, sheltered: Bool = false) -> Temps {
        let carCabin = snapshot?.interiorTempC.map(Double.init)
        let running = snapshot.map { $0.powerMode != 0 || $0.climateRunning } ?? false
        let outside = weather?.tempC ?? snapshot?.exteriorTempC.map(Double.init)
        guard let weather, !running else { return Temps(outsideC: outside, cabinC: carCabin, cabinEstimated: false) }
        let sun = sheltered ? 0 : weather.sunWm2
        let cabin = weather.tempC + fullSunGainC * min(max(sun / 900, 0), 1.1)
        return Temps(outsideC: outside, cabinC: cabin, cabinEstimated: true)
    }
}

/// Cooling estimates, as Volta makes them.
public enum Cooling {
    public static let targetC = 24

    /// Minutes of AC to bring the cabin from `cabinC` to about 24 °C.
    public static func minutes(cabinC: Double) -> Int {
        min(max(Int(((cabinC - Double(targetC)) * 0.6 + 3).rounded()), 3), 15)
    }

    /// Battery used, in %, for `minutes` of AC (about 2 kW).
    public static func batteryPercent(minutes: Int, capacityKwh: Double) -> Double {
        2.0 * Double(minutes) / 60 / capacityKwh * 100
    }
}

/// Should the app suggest turning the AC on? Only when it's daytime, the car is parked with the AC off, both the
/// cabin and the air are above your threshold, and no suggestion went out in the last two hours. It always asks;
/// the AC goes on only after you confirm with Face ID.
public enum PrecoolAdvisor {
    public static let defaultThresholdC = 29
    public static let cooldown: TimeInterval = 2 * 60 * 60
    public static let daytimeHours = 7..<19

    public struct Suggestion: Equatable, Sendable {
        public let cabinC: Double
        public let outsideC: Double
        public let minutes: Int
        public let batteryPercent: Double
    }

    public enum Skip: Equatable, Sendable {
        case off, night, coolingDown, noCarData, carRunning, noWeather, notHot
    }

    public static func decide(
        enabled: Bool,
        thresholdC: Int,
        snapshot: VehicleSnapshot?,
        weather: Weather?,
        capacityKwh: Double,
        lastSuggestedAt: Date?,
        now: Date,
        calendar: Calendar = .current,
        sheltered: Bool = false
    ) -> Result<Suggestion, SkipReason> {
        guard enabled else { return .failure(SkipReason(.off)) }
        guard daytimeHours.contains(calendar.component(.hour, from: now)) else { return .failure(SkipReason(.night)) }
        if let last = lastSuggestedAt, now.timeIntervalSince(last) < cooldown { return .failure(SkipReason(.coolingDown)) }
        guard let snapshot else { return .failure(SkipReason(.noCarData)) }
        guard snapshot.powerMode == 0, !snapshot.climateRunning else { return .failure(SkipReason(.carRunning)) }
        guard let weather else { return .failure(SkipReason(.noWeather)) }
        let t = CabinModel.temps(snapshot, weather: weather, sheltered: sheltered)
        guard let cabin = t.cabinC, let outside = t.outsideC else { return .failure(SkipReason(.noWeather)) }
        guard cabin > Double(thresholdC), outside > Double(thresholdC) else { return .failure(SkipReason(.notHot)) }
        let minutes = Cooling.minutes(cabinC: cabin)
        return .success(Suggestion(
            cabinC: cabin, outsideC: outside, minutes: minutes,
            batteryPercent: Cooling.batteryPercent(minutes: minutes, capacityKwh: capacityKwh)
        ))
    }

    /// `Skip` wrapped as an `Error` so it can sit in a `Result`.
    public struct SkipReason: Error, Equatable, Sendable {
        public let skip: Skip
        public init(_ skip: Skip) { self.skip = skip }
    }
}
