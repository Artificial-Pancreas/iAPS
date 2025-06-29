public enum MedtrumUpdatePatchResult {
    case success
    case failure(error: MedtrumUpdatePatchError)
}

public enum MedtrumUpdatePatchError: LocalizedError {
    case connectionFailure
    case unknownError(reason: String)
}
