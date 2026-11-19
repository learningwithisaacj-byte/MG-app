// Ported to Swift from Volta (Apache 2.0, https://github.com/irshadm/volta-android). See NOTICE.md.

import Foundation
import MGKit

/// The MG EVs the app knows. MG's model name can carry the trim ("COMET EV EXCLUSIVE FC") and its series can be a code
/// ("E230"), so each pattern is tried against both. The ZS Astor is a petrol car, not the ZS EV.
///
/// MG can also send the trim alone (a Windsor Pro came through as "Essence"). Trims only one model sells name it: FC and
/// Play / Plush / Pace are Comets, Excite Pro and Exclusive Plus are ZS EVs, Exclusive Pro and Essence Pro are Windsor Pros.
///
/// Only the Windsor's pack-energy reading has been checked against the car, so the battery size is learned from it on
/// the Windsor. Other models start from `packKwh`, the pack MG India sells; nil means not known yet.
public enum CarModel: String, CaseIterable, Codable, Sendable {
    case windsor, comet, zsEv, m9, cyberster, tomahawk, other

    public var label: String? {
        switch self {
        case .windsor: return "Windsor"
        case .comet: return "Comet EV"
        case .zsEv: return "ZS EV"
        case .m9: return "M9"
        case .cyberster: return "Cyberster"
        case .tomahawk: return "Hector Tomahawk EV"
        case .other: return nil
        }
    }

    public var packKwh: Double? {
        switch self {
        case .comet: return 17.3
        case .zsEv: return 50.3
        case .m9: return 90
        case .cyberster: return 77
        default: return nil
        }
    }

    private var pattern: String? {
        switch self {
        case .windsor: return #"windsor|\bEQ100\b"#
        case .comet: return #"comet|\bEC32\b|\bE230\b|\b(?:excite|exclusive)\s*fc\b|^\s*(?:play|plush|pace)\b"#
        case .zsEv: return #"^(?!.*astor).*(?:\bzs\b|\bexcite\s*pro\b|\bexclusive\s*(?:plus|\+))"#
        case .m9: return #"\bm9\b"#
        case .cyberster: return #"cyberster"#
        case .tomahawk: return #"tomahawk"#
        case .other: return nil
        }
    }

    /// The car's own pack-energy reading is in kWh. Only checked on the Windsor so far.
    public var reportsPackEnergy: Bool { self == .windsor }

    /// A name that is only a Windsor trim: Exclusive Pro, Essence Pro, or Essence. Tried after every model, so
    /// "ZS EV ESSENCE" stays a ZS EV.
    private static let windsorTrim = #"^\s*(?:(?:exclusive|essence)\s*pro|essence)\b"#

    public static func of(_ text: String) -> CarModel {
        func matches(_ p: String) -> Bool { text.range(of: p, options: [.regularExpression, .caseInsensitive]) != nil }
        if let m = allCases.first(where: { $0.pattern.map(matches) == true }) { return m }
        return matches(windsorTrim) ? .windsor : .other
    }
}

/// Which MG the signed-in account drives, named from the vehicle list MG returns at sign-in.
public struct CarIdentity: Equatable, Codable, Sendable {
    public let name: String
    public var model: CarModel { CarModel.of(name) }

    public init(name: String) { self.name = name }

    /// Before the first sign-in, or when MG sent no model.
    public static let unknown = CarIdentity(name: "Your MG")

    private static let pro = #"\bpro\b"#

    /// "COMET EV EXCLUSIVE FC" becomes "Comet EV". A model the app doesn't know keeps MG's name, without the brand.
    public static func of(_ vehicle: Vehicle?) -> CarIdentity {
        guard let raw = [vehicle?.model, vehicle?.series].compactMap({ $0 }).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return unknown
        }
        return named("\(vehicle?.model ?? "") \(vehicle?.series ?? "")", raw: raw)
    }

    public static func fromSaved(_ name: String) -> CarIdentity { named(name, raw: name) }

    private static func named(_ text: String, raw: String) -> CarIdentity {
        let model = CarModel.of(text)
        let name: String
        if model == .windsor, text.range(of: pro, options: [.regularExpression, .caseInsensitive]) != nil {
            name = "Windsor Pro"
        } else if let label = model.label {
            name = label
        } else {
            var n = raw.trimmingCharacters(in: .whitespaces)
            for prefix in ["MG ", "mg "] where n.hasPrefix(prefix) { n.removeFirst(prefix.count) }
            name = n.trimmingCharacters(in: .whitespaces)
        }
        return name.isEmpty ? unknown : CarIdentity(name: name)
    }
}
