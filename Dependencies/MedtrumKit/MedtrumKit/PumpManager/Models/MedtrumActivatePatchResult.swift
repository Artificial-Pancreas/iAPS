public enum MedtrumActivatePatchResult {
    case success
    case failure(error: MedtrumActivatePatchError)
}

public enum MedtrumActivatePatchError: LocalizedError {
    case connectionFailure(reason: String)
    case unknownError(reason: String)
    
    public var errorDescription: String? {
        switch self {
            case .connectionFailure(reason: let reason):
            return "Connection failure: \(reason)"
        case .unknownError(reason: let reason):
            return "Unknown error: \(reason)"
        }
    }
}
