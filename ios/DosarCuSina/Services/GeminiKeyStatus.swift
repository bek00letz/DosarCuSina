import Foundation

/// The outcome of testing a Gemini key, told apart so the screen can say what
/// to do next: check the internet, or check the key.
public enum GeminiKeyStatus: Sendable, Equatable {
    case valid
    /// Nothing was typed.
    case empty
    /// Google answered and refused the key.
    case invalidKey
    /// No internet, or Google couldn't be reached.
    case offline
    /// Google is busy or the key has used up its free quota.
    case rateLimited
    /// Google answered with something unexpected.
    case unavailable

    /// From the HTTP status of the test request.
    public init(statusCode: Int?) {
        switch statusCode {
        case 200?: self = .valid
        case 400?, 401?, 403?: self = .invalidKey
        case 429?: self = .rateLimited
        default: self = .unavailable
        }
    }

    /// From an error thrown before any answer came back.
    public init(error: any Error) {
        let offlineCodes: Set<URLError.Code> = [
            .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
            .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
        ]
        if let urlError = error as? URLError, offlineCodes.contains(urlError.code) {
            self = .offline
        } else {
            self = .unavailable
        }
    }
}
