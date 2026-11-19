import Foundation

/// Everything that can go wrong talking to MG's i-SMART servers. Each case carries what to show on screen.
public enum IsmartError: Error, Equatable {
    /// A general failure (network, unreadable reply, no vehicle).
    case failed(String)
    /// Input that can't be sent (a PIN that isn't 4 digits, a phone number that isn't 10).
    case invalidInput(String)
    /// The server rejected the credentials (bad password, unregistered, daily limit). Never retried automatically.
    case loginRejected(String)
    /// Multi-factor login is on for the account; MG wants an SMS code this app can't supply. Never retried.
    case mfaRequired(String)
    /// The session was taken (the MG app signed in) or expired; the saved login is still good.
    case signedOut
    /// More logins in an hour than `MGIsmartClient.maxLoginsPerHour`: the apps are taking the session from each other.
    case loginThrottled(retryAt: Date)
    /// A command was sent but its outcome is unknown. Must not be replayed automatically.
    case commandIndeterminate(String)
    /// MG said the control PIN is wrong. Wrong tries count against MG's limit, so it is never retried.
    case wrongPin(String)
    /// MG answered a status request with a result code we don't know. A read failed; nothing was sent to the car.
    case serverResult(label: String, result: Int, serverMessage: String?)
    /// A shared (secondary) account; battery data needs the owner account.
    case notOwner

    public var message: String {
        switch self {
        case let .failed(m), let .invalidInput(m), let .loginRejected(m), let .mfaRequired(m),
             let .commandIndeterminate(m), let .wrongPin(m):
            return m
        case .signedOut:
            return "Signed out by another app"
        case .loginThrottled:
            return "Signed in too often this hour"
        case let .serverResult(label, result, serverMessage):
            return "\(label) failed: " + (serverMessage.map { "\($0) (result \(result))" } ?? "result \(result)")
        case .notOwner:
            return "This MG account is a shared (secondary) account; battery data needs the owner account"
        }
    }

    /// What to show the person.
    public var userMessage: String {
        switch self {
        case let .serverResult(label, result, serverMessage):
            if let serverMessage { return "MG: \(serverMessage) (code \(result))" }
            return "MG's server couldn't get the car's \(label.lowercased()) (code \(result)). Try again in a minute."
        case .mfaRequired:
            return "Multi-factor login is on for this MG account. Turn it off in the MG app's security settings, then sign in again."
        case let .loginThrottled(retryAt):
            let f = DateFormatter()
            f.timeStyle = .short
            return "The MG app and this app keep signing each other out. Try again after \(f.string(from: retryAt))."
        default:
            return message
        }
    }

    /// True for the "signed out" family (`signedOut` and `loginThrottled`).
    public var isSignedOut: Bool {
        switch self {
        case .signedOut, .loginThrottled: return true
        default: return false
        }
    }

    /// True for the "rejected login" family (`loginRejected` and `mfaRequired`).
    public var isLoginRejected: Bool {
        switch self {
        case .loginRejected, .mfaRequired: return true
        default: return false
        }
    }
}

/// MG's rejection text when the account has multi-factor login on.
func mfaRequired(_ message: String) -> Bool {
    message.range(of: #"multi[\s-]?factor|\bmfa\b"#, options: [.regularExpression, .caseInsensitive]) != nil
}

/// The gateway says the session is gone. Usually code 7, but also other codes with "Login is invalid, please login again".
func sessionInvalid(_ message: String?) -> Bool {
    guard let m = message?.lowercased() else { return false }
    return (m.contains("login") && m.contains("invalid")) || m.contains("login again")
        || (m.contains("token") && (m.contains("invalid") || m.contains("expired")))
}
