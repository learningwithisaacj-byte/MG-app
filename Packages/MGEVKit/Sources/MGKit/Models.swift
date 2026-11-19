// Ported to Swift from Volta (Apache 2.0, https://github.com/irshadm/volta-android), itself a Kotlin port of
// mg-ismart-india-client by John Lazarus (MIT, https://github.com/john-lazarus/mg-ismart-india-client).
// See NOTICE.md for both licences.

import Foundation

public struct Vehicle: Equatable, Codable, Sendable {
    public let vin: String
    public let series: String?
    public let model: String?
    public let colorName: String?
    public let isSubAccount: Bool

    public init(vin: String, series: String?, model: String?, colorName: String?, isSubAccount: Bool) {
        self.vin = vin
        self.series = series
        self.model = model
        self.colorName = colorName
        self.isSubAccount = isSubAccount
    }
}

public struct Tyres: Equatable, Codable, Sendable {
    public let frontLeft: Double
    public let frontRight: Double
    public let rearLeft: Double
    public let rearRight: Double

    public init(frontLeft: Double, frontRight: Double, rearLeft: Double, rearRight: Double) {
        self.frontLeft = frontLeft
        self.frontRight = frontRight
        self.rearLeft = rearLeft
        self.rearRight = rearRight
    }

    public var all: [Double] { [frontLeft, frontRight, rearLeft, rearRight] }
}

/// Full status in real units. India is right-hand drive: the protocol's `driverDoor` is the front-right door.
public struct VehicleSnapshot: Equatable, Codable, Sendable {
    public var statusTime: Int64
    public var socPercent: Int?
    public var rangeKm: Double?
    public var odometerKm: Double?
    public var locked: Bool
    public var driverDoorOpen: Bool
    public var passengerDoorOpen: Bool
    public var rearLeftDoorOpen: Bool
    public var rearRightDoorOpen: Bool
    public var bootOpen: Bool
    public var bonnetOpen: Bool
    public var anyWindowOpen: Bool
    public var lightsOn: Bool
    public var climateRunning: Bool
    public var interiorTempC: Int?
    public var exteriorTempC: Int?
    public var auxVolts: Double?
    public var tyres: Tyres?
    public var journeyId: Int64
    public var journeyDistanceRaw: Int
    public var latitude: Double?
    public var longitude: Double?
    public var altitudeM: Int?
    public var gpsTime: Int64?
    public var activeAlerts: [Int]
    /// Raw power mode / engine status: 0 when parked and off; non-zero is taken as ignition on.
    public var powerMode: Int = 0
    public var engineStatus: Int = 0
    public var speedKmh: Double?
    public var driverWindowOpen: Bool?
    public var passengerWindowOpen: Bool?
    public var rearLeftWindowOpen: Bool?
    public var rearRightWindowOpen: Bool?
    public var sunroofOpen: Bool?
    public var sideLights = false
    public var dippedBeam = false
    public var mainBeam = false
    public var handBrakeOn: Bool?
    public var headingDeg: Int?

    public var anyDoorOpen: Bool {
        driverDoorOpen || passengerDoorOpen || rearLeftDoorOpen || rearRightDoorOpen || bootOpen || bonnetOpen
    }

    /// The car's own warning codes include low tyre pressure (code 4).
    public var tyreWarning: Bool { activeAlerts.contains(4) }

    public static func from(_ f: Tap.StatusFrame) -> VehicleSnapshot {
        let b = f.basic
        var driverWindow = b.driverWindow == true
        // MG India sometimes reports a stale driver-window bit on a fully closed, locked car.
        let anythingElseOpen = b.driverDoor || b.passengerDoor || b.rearLeftDoor || b.rearRightDoor || b.boot || b.bonnet ||
            b.passengerWindow == true || b.rearLeftWindow == true || b.rearRightWindow == true
        if driverWindow && b.locked && !anythingElseOpen { driverWindow = false }
        let t = TyreScale.psi([b.tyreFrontLeft, b.tyreFrontRight, b.tyreRearLeft, b.tyreRearRight])
        let tyres: Tyres? = t.allSatisfy { $0 != nil } ? Tyres(frontLeft: t[0]!, frontRight: t[1]!, rearLeft: t[2]!, rearRight: t[3]!) : nil
        let hasFix = f.position.gpsStatus >= 2
        return VehicleSnapshot(
            statusTime: f.statusTime,
            socPercent: (0...100).contains(b.fuelLevelPrc) ? b.fuelLevelPrc : nil,
            rangeKm: Double(b.fuelRange) / 10,
            odometerKm: Double(b.mileage) / 10,
            locked: b.locked,
            driverDoorOpen: b.driverDoor,
            passengerDoorOpen: b.passengerDoor,
            rearLeftDoorOpen: b.rearLeftDoor,
            rearRightDoorOpen: b.rearRightDoor,
            bootOpen: b.boot,
            bonnetOpen: b.bonnet,
            anyWindowOpen: driverWindow || b.passengerWindow == true || b.rearLeftWindow == true || b.rearRightWindow == true,
            lightsOn: b.sideLights || b.dippedBeam || b.mainBeam,
            climateRunning: (2...3).contains(b.remoteClimate),
            interiorTempC: (-60...90).contains(b.interiorTemp) ? b.interiorTemp : nil,
            exteriorTempC: (-60...90).contains(b.exteriorTemp) ? b.exteriorTemp : nil,
            auxVolts: Double(b.batteryVoltage) / 10,
            tyres: tyres,
            journeyId: b.journeyId,
            journeyDistanceRaw: b.journeyDistance,
            latitude: hasFix ? Double(f.position.latitudeMicro) / 1e6 : nil,
            longitude: hasFix ? Double(f.position.longitudeMicro) / 1e6 : nil,
            altitudeM: hasFix ? f.position.altitudeM : nil,
            gpsTime: f.position.timeSeconds > 0 ? f.position.timeSeconds : nil,
            activeAlerts: f.alerts.filter { $0.value != 0 }.map(\.id),
            powerMode: b.powerMode,
            engineStatus: b.engineStatus,
            speedKmh: f.position.speedTenths >= 0 ? Double(f.position.speedTenths) / 10 : nil,
            driverWindowOpen: b.driverWindow.map { _ in driverWindow },
            passengerWindowOpen: b.passengerWindow,
            rearLeftWindowOpen: b.rearLeftWindow,
            rearRightWindowOpen: b.rearRightWindow,
            sunroofOpen: b.sunroof,
            sideLights: b.sideLights,
            dippedBeam: b.dippedBeam,
            mainBeam: b.mainBeam,
            handBrakeOn: b.handBrake,
            headingDeg: hasFix ? f.position.heading : nil
        )
    }
}

/// EV charging frame in real units.
public struct ChargeStatus: Equatable, Codable, Sendable {
    public var statusTime: Int64
    public var charging: Bool
    public var pluggedIn: Bool
    public var socPercent: Double?
    public var rangeKm: Double
    public var batteryEnergyKwh: Double
    public var voltageV: Double
    public var currentA: Double
    public var minutesRemaining: Int?
    public var odometerKm: Double
    public var distanceSinceChargeKm: Double?
    public var energySinceChargeKwh: Double?
    public var chargingType: Int
    public var startedAt: Int64?
    public var endedAt: Int64?
    public var kmToday: Double?
    public var kwhToday: Double?

    /// Instantaneous charging power in kW (voltage x current), 0 when idle.
    public var powerKw: Double { charging ? voltageV * currentA / 1000 : 0 }

    public static func from(_ f: Tap.ChargeFrame) -> ChargeStatus {
        ChargeStatus(
            statusTime: f.statusTime,
            charging: f.charging,
            pluggedIn: f.gunConnected,
            socPercent: f.powerLevelPrc.flatMap { (0...1000).contains($0) ? Double($0) / 10 : nil },
            rangeKm: Double(f.fuelRange) / 10,
            batteryEnergyKwh: Double(f.realtimePower) / 10,
            voltageV: Double(f.voltage) * 0.25,
            currentA: 1000 - Double(f.current) * 0.05,
            minutesRemaining: f.timeLevelPrc.flatMap { $0 == 0xFFFF ? nil : $0 },
            odometerKm: Double(f.mileage) / 10,
            distanceSinceChargeKm: f.mileageSinceCharge.map { Double($0) / 10 },
            energySinceChargeKwh: f.powerUsageSinceCharge.map { Double($0) / 10 },
            chargingType: f.chargingType,
            startedAt: f.startTime.flatMap { $0 > 0 ? $0 : nil },
            endedAt: f.endTime.flatMap { $0 > 0 ? $0 : nil },
            kmToday: f.mileageOfDay.map { Double($0) / 10 },
            kwhToday: f.powerUsageOfDay.map { Double($0) / 10 }
        )
    }
}

/// Remote commands: the type and parameters the MG app sends.
public enum RemoteCommand: String, CaseIterable, Sendable {
    case lock, unlock, climateOn, climateOff, findMyCar, openBoot, windowsOpen, windowsClose

    public var label: String {
        switch self {
        case .lock: return "Lock"
        case .unlock: return "Unlock"
        case .climateOn: return "AC on"
        case .climateOff: return "AC off"
        case .findMyCar: return "Find my car"
        case .openBoot: return "Open boot"
        case .windowsOpen: return "Open windows"
        case .windowsClose: return "Close windows"
        }
    }

    public var type: Int {
        switch self {
        case .lock: return 1
        case .unlock, .openBoot: return 2
        case .climateOn, .climateOff: return 6
        case .findMyCar: return 0
        case .windowsOpen, .windowsClose: return 3
        }
    }

    public var params: [(Int, Int)] {
        switch self {
        case .lock: return []
        case .unlock: return [(4, 0), (5, 0), (6, 0), (7, 3), (255, 0)]
        case .climateOn: return [(19, 3), (20, 3), (255, 0)]
        case .climateOff: return [(19, 0), (20, 0), (255, 0)]
        case .findMyCar: return [(1, 1), (2, 1), (3, 1), (255, 0)]
        case .openBoot: return [(4, 0), (5, 0), (6, 0), (7, 2), (255, 0)]
        // Params 9-12 pick the windows (the two front ones), 13 = 3 open / 0 close.
        case .windowsOpen: return [(8, 0), (9, 1), (10, 1), (11, 0), (12, 0), (13, 3)]
        case .windowsClose: return [(8, 0), (9, 1), (10, 1), (11, 0), (12, 0), (13, 0)]
        }
    }
}

/// Tyre pressures arrive as one raw number per wheel, scaled differently by car. The Windsor counts in 0.2 psi steps
/// (169 is 33.8 psi). The ZS EV and other SAIC cars count in 0.04 bar steps (70 is 2.8 bar, about 41 psi). On the
/// Windsor's scale a number under 100 is under 20 psi, so when every wheel reads under 100 the car uses the bar scale.
enum TyreScale {
    static let psiPerUnit = 0.2
    static let barPerUnit = 0.04
    static let psiPerBar = 14.5038
    static let barScaleMaxRaw = 99

    static func psi(_ raws: [Int?]) -> [Double?] {
        let valid = raws.map { raw in raw.flatMap { (1...255).contains($0) ? $0 : nil } }
        let present = valid.compactMap { $0 }
        let barScale = !present.isEmpty && present.allSatisfy { $0 <= barScaleMaxRaw }
        return valid.map { raw in
            raw.map {
                let psi = barScale ? Double($0) * barPerUnit * psiPerBar : Double($0) * psiPerUnit
                return (psi * 10).rounded() / 10
            }
        }
    }
}
