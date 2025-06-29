public enum MedtrumPrimePatchResult {
    case success
    case failure(error: MedtrumPrimePatchError)
}

public enum MedtrumPrimePatchError: LocalizedError {
    case needToDeactivateFirst
    case connectionFailure
    case noKnownPumpBase
    case unknownError(reason: String)
}
