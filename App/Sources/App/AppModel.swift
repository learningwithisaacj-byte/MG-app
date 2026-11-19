import EVCore
import Foundation
import LocalAuthentication
import MGKit
import Observation

/// The app's state and the one MG client every screen shares.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case signedOut, ready }

    private(set) var phase: Phase
    private(set) var reading: SavedReading?
    private(set) var refreshing = false
    private(set) var sendingCommand: RemoteCommand?
    /// A message for the person (an error, or the result of a command), shown once.
    var notice: Notice?
    /// A command waiting for the control PIN to be entered.
    var commandAwaitingPin: RemoteCommand?

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    let secure: SecureStore
    let car: CarStore
    let client: MGIsmartClient

    init(secure: SecureStore = .shared, car: CarStore = CarStore()) {
        self.secure = secure
        self.car = car
        self.client = MGIsmartClient(credentials: { SecureStore.shared.credentials }, sessions: secure)
        self.phase = secure.credentials == nil ? .signedOut : .ready
        self.reading = car.lastReading
    }

    /// Whether a control PIN hash is saved (observable, unlike the Keychain itself).
    private(set) var hasPin = SecureStore.shared.pinHash != nil

    var identity: CarIdentity { car.identity }

    func forgetPin() {
        secure.pinHash = nil
        hasPin = false
    }
    var profile: VehicleProfile { car.profile }

    // MARK: - Sign-in

    /// Signs in with the i-SMART mobile number and password. A rejected password is never retried, because each
    /// try counts against MG's daily limit.
    func signIn(phone: String, password: String) async throws {
        let creds = Credentials(phone: try MGCrypto.normalizePhone(phone), password: password)
        secure.credentials = creds
        do {
            try await client.signIn()
            let vehicles = try await client.vehicles()
            guard let first = vehicles.first else { throw IsmartError.failed("No car is linked to this MG account") }
            if first.isSubAccount { throw IsmartError.notOwner }
            let identity = CarIdentity.of(first)
            if identity != car.identity {
                car.clear()
                car.identity = identity
            }
            phase = .ready
            await refresh()
        } catch {
            secure.clear()
            throw error
        }
    }

    func signOut() async {
        await client.signOut()
        secure.clear()
        car.clear()
        hasPin = false
        reading = nil
        phase = .signedOut
    }

    // MARK: - Status

    func refresh() async {
        guard phase == .ready, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let r = try await client.read()
            let saved = SavedReading(snapshot: r.snapshot, charge: r.charge, fetchedAt: Date())
            reading = saved
            car.lastReading = saved
            car.learnCapacity(from: r.charge)
        } catch {
            show(error)
        }
    }

    // MARK: - Commands

    /// Face ID first, then the control PIN (asked once, its hash kept in the Keychain), then the command.
    func send(_ command: RemoteCommand) async {
        guard sendingCommand == nil else { return }
        guard await Self.confirmWithBiometrics(reason: "\(command.label) on your car") else { return }
        guard let pinHash = secure.pinHash else {
            commandAwaitingPin = command
            return
        }
        await run(command, pinHash: pinHash)
    }

    /// Called from the PIN sheet. MG checks the PIN before the command goes to the car.
    func enterPin(_ pin: String) async {
        guard let command = commandAwaitingPin else { return }
        commandAwaitingPin = nil
        do {
            let hash = try MGCrypto.pinHash(pin)
            secure.pinHash = hash
            hasPin = true
            await run(command, pinHash: hash)
        } catch {
            show(error)
        }
    }

    private func run(_ command: RemoteCommand, pinHash: String) async {
        sendingCommand = command
        defer { sendingCommand = nil }
        do {
            try await client.command(command, pinHash: pinHash)
            notice = Notice(text: "\(command.label): done", isError: false)
            await refresh()
        } catch let e as IsmartError {
            if case .wrongPin = e { forgetPin() }
            show(e)
        } catch {
            show(error)
        }
    }

    private func show(_ error: Error) {
        let text = (error as? IsmartError)?.userMessage ?? error.localizedDescription
        notice = Notice(text: text, isError: true)
    }

    static func confirmWithBiometrics(reason: String) async -> Bool {
        let context = LAContext()
        var err: NSError?
        // Face ID or Touch ID, falling back to the passcode; a phone with neither set up just proceeds.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
