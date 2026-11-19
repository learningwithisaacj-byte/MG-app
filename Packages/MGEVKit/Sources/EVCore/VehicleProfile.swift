// Ported to Swift from Volta (Apache 2.0, https://github.com/irshadm/volta-android). See NOTICE.md.

import Foundation

/// One point on the DC charging curve: charging power available at a given state of charge.
public struct ChargeCurvePoint: Equatable, Codable, Sendable {
    public let socPercent: Int
    public let powerKw: Double
    public init(_ socPercent: Int, _ powerKw: Double) {
        self.socPercent = socPercent
        self.powerKw = powerKw
    }
}

/// Energy model inputs for the car. Defaults are for the MG Windsor 38 kWh: usable capacity was measured on a real car
/// (21.9 kWh at 59 %) and is only a starting point; `CapacityLearning` replaces it with the car's own figure after a
/// few reads. Efficiencies are starting points that drive logging replaces with learned values.
public struct VehicleProfile: Equatable, Codable, Sendable {
    public var usableCapacityKwh: Double
    public var cityKmPerKwh: Double
    public var highwayKmPerKwh: Double
    public var massKg: Double
    public var driveEfficiency: Double
    public var regenEfficiency: Double
    public var dcCurve: [ChargeCurvePoint]

    public init(
        usableCapacityKwh: Double = 37.1, cityKmPerKwh: Double = 7.0, highwayKmPerKwh: Double = 6.0, massKg: Double = 1600,
        driveEfficiency: Double = 0.88, regenEfficiency: Double = 0.60, dcCurve: [ChargeCurvePoint] = VehicleProfile.windsor38DcCurve
    ) {
        self.usableCapacityKwh = usableCapacityKwh
        self.cityKmPerKwh = cityKmPerKwh
        self.highwayKmPerKwh = highwayKmPerKwh
        self.massKg = massKg
        self.driveEfficiency = driveEfficiency
        self.regenEfficiency = regenEfficiency
        self.dcCurve = dcCurve
    }

    /// A starting profile for `model`: its sold pack size where known, the Windsor's otherwise.
    public static func starting(for model: CarModel) -> VehicleProfile {
        var p = VehicleProfile()
        if let pack = model.packKwh { p.usableCapacityKwh = pack }
        return p
    }

    public func energyAt(_ socPercent: Double) -> Double {
        usableCapacityKwh * min(max(socPercent, 0), 100) / 100
    }

    /// Flat-road range from `socPercent` down to `reservePercent` at the given efficiency.
    public func rangeKm(_ socPercent: Double, kmPerKwh: Double, reservePercent: Double = 0) -> Double {
        max(energyAt(socPercent) - energyAt(reservePercent), 0) * kmPerKwh
    }

    public func cityRangeKm(_ socPercent: Double) -> Double { rangeKm(socPercent, kmPerKwh: cityKmPerKwh) }
    public func highwayRangeKm(_ socPercent: Double) -> Double { rangeKm(socPercent, kmPerKwh: highwayKmPerKwh) }

    /// Human-readable problems; empty when the profile is usable.
    public func validate() -> [String] {
        var out: [String] = []
        if !(10...120).contains(usableCapacityKwh) { out.append("Usable capacity must be 10–120 kWh") }
        if !(2...15).contains(cityKmPerKwh) { out.append("City efficiency must be 2–15 km/kWh") }
        if !(2...15).contains(highwayKmPerKwh) { out.append("Highway efficiency must be 2–15 km/kWh") }
        if !(800...3500).contains(massKg) { out.append("Mass must be 800–3500 kg") }
        if !(0.5...1.0).contains(driveEfficiency) { out.append("Drive efficiency must be 0.5–1.0") }
        if !(0...0.9).contains(regenEfficiency) { out.append("Regen efficiency must be 0–0.9") }
        if dcCurve.count < 2 || zip(dcCurve, dcCurve.dropFirst()).contains(where: { $1.socPercent <= $0.socPercent }) {
            out.append("Charging curve needs at least 2 points in increasing SoC order")
        }
        return out
    }

    /// Assumed curve (about 45 kW peak, tapering above 50 %); calibrated from charge sessions later.
    public static let windsor38DcCurve: [ChargeCurvePoint] = [
        .init(0, 40), .init(10, 45), .init(50, 45), .init(65, 35), .init(80, 25), .init(90, 12), .init(100, 5),
    ]
}

/// Learns the usable battery size from the car instead of assuming the Windsor 38's 37.1 kWh.
///
/// The charge frame reports the pack's energy next to its state of charge, so one reading gives
/// `energy / (soc / 100)`. Low readings are skipped (a whole-percent SoC is too coarse below 20 %), and the median of
/// the last few samples is used so one bad frame can't move the profile.
public enum CapacityLearning {
    public static let minSocPercent = 20.0
    public static let minSamples = 3
    public static let maxSamples = 8
    public static let changeKwh = 0.5

    /// One reading's estimate of usable capacity, or nil when the reading can't support one.
    public static func sample(socPercent: Double, energyKwh: Double?) -> Double? {
        guard let energyKwh, energyKwh >= 1, (minSocPercent...100).contains(socPercent) else { return nil }
        let kwh = energyKwh / (socPercent / 100)
        return (10...120).contains(kwh) ? kwh : nil
    }

    public static func append(_ samples: [Double], _ sample: Double) -> [Double] {
        Array((samples + [sample]).suffix(maxSamples))
    }

    /// The learned capacity (median, to 0.1 kWh) once there are enough samples; nil before that.
    public static func learned(_ samples: [Double]) -> Double? {
        guard samples.count >= minSamples else { return nil }
        let sorted = samples.sorted()
        let mid = sorted.count / 2
        let median = sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        return (median * 10).rounded() / 10
    }

    public static func shouldReplace(current: Double, learned: Double) -> Bool {
        abs(learned - current) >= changeKwh - 1e-9
    }
}
