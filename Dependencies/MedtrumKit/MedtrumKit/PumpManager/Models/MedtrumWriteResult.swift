enum MedtrumWriteResult<T> {
    case success(data: T)
    case failure(error: MedtrumWriteError)
}

enum MedtrumWriteError: LocalizedError {
    case timeout
    case invalidData
    case invalidResponse(code: UInt16)
    case noManager
    case noWriteCharacteristic

    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "Timeout hit"
        case .invalidData:
            return "Invalid data received"
        case let .invalidResponse(code):
            return "Invalid response code: \(code)"
        case .noManager:
            return "No peripheral manager"
        case .noWriteCharacteristic:
            return "No write characteristic. Device might be disconnected"
        }
    }
}
