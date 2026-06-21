import Foundation

enum LoopOutcome: JSON {
    case enacted(Suggestion, timestamp: Date) // closed loop, enacted
    case enactFailed(Suggestion, error: String, timestamp: Date) // closed loop, enact failed
    case suggested(Suggestion, timestamp: Date) // open loop
    case failed(error: String, timestamp: Date) // determineBasal error
}

extension LoopOutcome {
    var timestamp: Date {
        switch self {
        case let .enacted(_, timestamp: t): return t
        case let .enactFailed(_, _, timestamp: t): return t
        case let .suggested(_, timestamp: t): return t
        case let .failed(_, timestamp: t): return t
        }
    }

    var error: String? {
        switch self {
        case let .enactFailed(_, error: e, _): return e
        case let .failed(e, _): return e
        default: return nil
        }
    }

    var suggestion: Suggestion? {
        switch self {
        case let .enacted(s, _): return s
        case let .enactFailed(s, _, _): return s
        case let .suggested(s, _): return s
        case .failed: return nil
        }
    }

    var enactedSuggestion: Suggestion? {
        switch self {
        case let .enacted(s, _): return s
        case let .enactFailed(s, _, _): return s
        case .suggested: return nil
        case .failed: return nil
        }
    }
}
