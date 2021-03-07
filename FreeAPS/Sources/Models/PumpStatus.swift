struct PumpStatus: JSON {
    let status: StatusType
    let bolusing: Bool
    let suspended: Bool
}

enum StatusType: String, JSON {
    case normal
    case suspended
    case bolusing
}
