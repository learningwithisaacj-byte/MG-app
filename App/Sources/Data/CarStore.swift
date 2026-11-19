import EVCore
import Foundation
import MGKit

/// Non-secret things the app remembers about the car, in UserDefaults: which car it is, its battery profile, the
/// capacity samples it is learning from, and the last reading so the dashboard opens instantly.
struct CarStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var identity: CarIdentity {
        get { defaults.string(forKey: "car.name").map(CarIdentity.fromSaved) ?? .unknown }
        nonmutating set { defaults.set(newValue.name, forKey: "car.name") }
    }

    var profile: VehicleProfile {
        get { decode(VehicleProfile.self, "car.profile") ?? .starting(for: identity.model) }
        nonmutating set { encode(newValue, "car.profile") }
    }

    var capacitySamples: [Double] {
        get { defaults.array(forKey: "car.capacitySamples") as? [Double] ?? [] }
        nonmutating set { defaults.set(newValue, forKey: "car.capacitySamples") }
    }

    var lastReading: SavedReading? {
        get { decode(SavedReading.self, "car.lastReading") }
        nonmutating set { encode(newValue, "car.lastReading") }
    }

    func clear() {
        for key in ["car.name", "car.profile", "car.capacitySamples", "car.lastReading"] { defaults.removeObject(forKey: key) }
    }

    /// Learns the battery size from a charge frame (Windsor only, until other models' readings are checked).
    func learnCapacity(from charge: ChargeStatus?) {
        guard identity.model.reportsPackEnergy, let charge, let soc = charge.socPercent,
              let sample = CapacityLearning.sample(socPercent: soc, energyKwh: charge.batteryEnergyKwh) else { return }
        let samples = CapacityLearning.append(capacitySamples, sample)
        capacitySamples = samples
        var p = profile
        if let learned = CapacityLearning.learned(samples), CapacityLearning.shouldReplace(current: p.usableCapacityKwh, learned: learned) {
            p.usableCapacityKwh = learned
            profile = p
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func encode<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

/// A reading as kept between launches.
struct SavedReading: Codable, Equatable {
    let snapshot: VehicleSnapshot
    let charge: ChargeStatus?
    let fetchedAt: Date
}
