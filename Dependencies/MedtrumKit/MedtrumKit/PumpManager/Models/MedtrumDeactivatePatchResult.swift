public enum MedtrumDeactivatePatchResult {
    case success
    case failure(error: MedtrumDeactivatePatchError)
}

public enum MedtrumDeactivatePatchError: LocalizedError {
    case connectionFailure
    case unknownError(reason: String)
}
