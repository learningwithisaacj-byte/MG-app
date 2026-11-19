import EVCore
import MGKit
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let r = model.reading {
                        BatteryCard(snapshot: r.snapshot, charge: r.charge, profile: model.profile, fetchedAt: r.fetchedAt)
                        ControlsCard()
                        CarStateCard(snapshot: r.snapshot)
                        TyresCard(tyres: r.snapshot.tyres, carWarning: r.snapshot.tyreWarning)
                    } else if model.refreshing {
                        ProgressView("Asking your car…").padding(.top, 80)
                    } else {
                        ContentUnavailableView(
                            "No reading yet",
                            systemImage: "car",
                            description: Text("Pull down to ask your car for its status.")
                        )
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(model.identity.name)
            .refreshable { await model.refresh() }
            .toolbar {
                if model.refreshing && model.reading != nil {
                    ToolbarItem(placement: .topBarTrailing) { ProgressView() }
                }
            }
            .sheet(item: $model.commandAwaitingPin) { command in
                ControlPinSheet(command: command)
                    .presentationDetents([.medium])
            }
            .alert(item: $model.notice) { notice in
                Alert(title: Text(notice.isError ? "Couldn't do that" : "Done"), message: Text(notice.text))
            }
        }
    }
}

extension RemoteCommand: Identifiable {
    public var id: String { rawValue }
}

// MARK: - Battery

struct BatteryCard: View {
    let snapshot: VehicleSnapshot
    let charge: ChargeStatus?
    let profile: VehicleProfile
    let fetchedAt: Date

    private var soc: Double? { charge?.socPercent ?? snapshot.socPercent.map(Double.init) }

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 20) {
                BatteryRing(percent: soc ?? 0, charging: charge?.charging == true)
                    .frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: 6) {
                    if let soc {
                        Text("\(Int(soc.rounded())) %").font(.system(size: 40, weight: .bold, design: .rounded))
                    }
                    if let soc {
                        Text("About \(Int(profile.highwayRangeKm(soc))) to \(Int(profile.cityRangeKm(soc))) km")
                            .font(.headline)
                        Text("highway to city, on your car's battery size")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let car = snapshot.rangeKm {
                        Text("Car says \(Int(car)) km").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let charge, charge.pluggedIn {
                Divider()
                ChargingRow(charge: charge)
            }
            Text("Updated \(fetchedAt.formatted(.relative(presentation: .named)))")
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct ChargingRow: View {
    let charge: ChargeStatus

    var body: some View {
        HStack {
            Image(systemName: charge.charging ? "bolt.fill" : "powerplug.fill")
                .foregroundStyle(charge.charging ? Color.green : Color.secondary)
            if charge.charging {
                Text(String(format: "Charging at %.1f kW", charge.powerKw))
                Spacer()
                if let m = charge.minutesRemaining {
                    Text("\(m / 60) h \(m % 60) min left").foregroundStyle(.secondary)
                }
            } else {
                Text("Plugged in, not charging")
                Spacer()
            }
        }
        .font(.subheadline)
    }
}

struct BatteryRing: View {
    let percent: Double
    let charging: Bool

    private var color: Color {
        switch percent {
        case ..<20: return .red
        case ..<40: return .orange
        default: return .green
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 12)
            Circle()
                .trim(from: 0, to: min(max(percent, 0), 100) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: charging ? "bolt.car.fill" : "car.fill")
                .font(.title)
                .foregroundStyle(color)
        }
        .accessibilityElement()
        .accessibilityLabel("Battery \(Int(percent)) percent\(charging ? ", charging" : "")")
    }
}

// MARK: - Controls

struct ControlsCard: View {
    @Environment(AppModel.self) private var model

    private var climateOn: Bool { model.reading?.snapshot.climateRunning == true }
    private var locked: Bool { model.reading?.snapshot.locked == true }

    var body: some View {
        Card {
            HStack(spacing: 12) {
                ControlButton(title: locked ? "Unlock" : "Lock", icon: locked ? "lock.open.fill" : "lock.fill",
                              command: locked ? .unlock : .lock)
                ControlButton(title: climateOn ? "AC off" : "AC on", icon: climateOn ? "fan.slash.fill" : "fan.fill",
                              command: climateOn ? .climateOff : .climateOn)
                ControlButton(title: "Find", icon: "speaker.wave.2.fill", command: .findMyCar)
            }
        }
    }
}

struct ControlButton: View {
    @Environment(AppModel.self) private var model
    let title: String
    let icon: String
    let command: RemoteCommand

    var body: some View {
        Button {
            Task { await model.send(command) }
        } label: {
            VStack(spacing: 6) {
                if model.sendingCommand == command {
                    ProgressView().frame(height: 24)
                } else {
                    Image(systemName: icon).font(.title2).frame(height: 24)
                }
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(model.sendingCommand != nil)
    }
}

// MARK: - Doors, windows, 12 V

struct CarStateCard: View {
    let snapshot: VehicleSnapshot

    var body: some View {
        Card {
            StateRow(icon: snapshot.locked ? "lock.fill" : "lock.open.fill", text: snapshot.locked ? "Locked" : "Unlocked",
                     warn: !snapshot.locked)
            StateRow(icon: "door.left.hand.open", text: snapshot.anyDoorOpen ? openDoors : "Doors, boot and bonnet closed",
                     warn: snapshot.anyDoorOpen)
            StateRow(icon: "window.vertical.open", text: snapshot.anyWindowOpen ? "A window is open" : "Windows closed",
                     warn: snapshot.anyWindowOpen)
            if snapshot.climateRunning { StateRow(icon: "fan.fill", text: "AC is running", warn: false) }
            if let t = snapshot.interiorTempC {
                StateRow(icon: "thermometer.medium", text: "Inside \(t) °C" + (snapshot.exteriorTempC.map { ", outside \($0) °C" } ?? ""), warn: false)
            }
            if let v = snapshot.auxVolts {
                StateRow(icon: "minus.plus.batteryblock", text: String(format: "12 V battery %.1f V", v), warn: v < 11.8)
            }
            if let odo = snapshot.odometerKm {
                StateRow(icon: "gauge.with.dots.needle.33percent", text: "\(Int(odo).formatted()) km on the clock", warn: false)
            }
        }
    }

    private var openDoors: String {
        var parts: [String] = []
        // India is right-hand drive: the driver's door is the front right.
        if snapshot.driverDoorOpen { parts.append("front right door") }
        if snapshot.passengerDoorOpen { parts.append("front left door") }
        if snapshot.rearLeftDoorOpen { parts.append("rear left door") }
        if snapshot.rearRightDoorOpen { parts.append("rear right door") }
        if snapshot.bootOpen { parts.append("boot") }
        if snapshot.bonnetOpen { parts.append("bonnet") }
        return "Open: " + parts.joined(separator: ", ")
    }
}

struct StateRow: View {
    let icon: String
    let text: String
    let warn: Bool

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon).foregroundStyle(warn ? Color.orange : Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

// MARK: - Tyres

struct TyresCard: View {
    let tyres: Tyres?
    let carWarning: Bool
    /// The door-sticker pressure. Settings will make it editable in milestone 5.
    var targetPsi: Double = 33

    var body: some View {
        Card {
            HStack {
                Text("Tyres").font(.headline)
                Spacer()
                if carWarning { Label("Car warns of low pressure", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
            }
            if let tyres {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        TyreCell(name: "Front left", psi: tyres.frontLeft, target: targetPsi)
                        TyreCell(name: "Front right", psi: tyres.frontRight, target: targetPsi)
                    }
                    GridRow {
                        TyreCell(name: "Rear left", psi: tyres.rearLeft, target: targetPsi)
                        TyreCell(name: "Rear right", psi: tyres.rearRight, target: targetPsi)
                    }
                }
            } else {
                Text("Your car didn't report tyre pressures this time.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct TyreCell: View {
    let name: String
    let psi: Double
    let target: Double

    private var low: Bool { target - psi >= 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(String(format: "%.1f psi", psi)).font(.title3.weight(.semibold)).foregroundStyle(low ? Color.orange : Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Shared

struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
