public enum PatchState: UInt8, Codable {
    case none = 0
    case idle = 1
    case filled = 2
    case priming = 3
    case primed = 4
    case ejecting = 5
    case ejected = 6
    case active = 32
    case active_alt = 33
    case lowBgSuspended = 64
    case lowBgSuspended2 = 65
    case autoSuspended = 66
    case hourlyMaxSuspended = 67
    case dailyMaxSuspended = 68
    case suspended = 69
    case paused = 70
    case occlusion = 96
    case expired = 97
    case reservoirEmpty = 98
    case patchFault = 99
    case patchFaultd2 = 100
    case baseFault = 101
    case batteryOut = 102
    case noCalibration = 103
    case stopped = 128

    var description: String {
        switch self {
        case .none:
            return LocalizedString("None", comment: "Patch state for none")
        case .idle:
            return LocalizedString("Idle", comment: "Patch state for idle")
        case .filled:
            return LocalizedString("Filled", comment: "Patch state for filled")
        case .priming:
            return LocalizedString("Priming", comment: "Patch state for priming")
        case .primed:
            return LocalizedString("Primed", comment: "Patch state for primed")
        case .ejecting:
            return LocalizedString("Ejecting", comment: "Patch state for ejecting")
        case .ejected:
            return LocalizedString("Ejected", comment: "Patch state for ejected")
        case .active,
             .active_alt:
            return LocalizedString("Active", comment: "Patch state for active, active_alt")
        case .lowBgSuspended,
             .lowBgSuspended2:
            return LocalizedString("Suspended - Low BG", comment: "Patch state for lowBgSuspended, lowBgSuspended2")
        case .autoSuspended:
            return LocalizedString("Suspended - Auto", comment: "Patch state for autoSuspended")
        case .hourlyMaxSuspended:
            return LocalizedString("Suspended - Hourly max", comment: "Patch state for hourlyMaxSuspended")
        case .dailyMaxSuspended:
            return LocalizedString("Suspended - Daily max", comment: "Patch state for dailyMaxSuspended")
        case .suspended:
            return LocalizedString("Suspended", comment: "Patch state for suspended")
        case .paused:
            return LocalizedString("Paused", comment: "Patch state for paused")
        case .occlusion:
            return LocalizedString("Occlusion", comment: "Patch state for occlusion")
        case .expired:
            return LocalizedString("Expired", comment: "Patch state for expired")
        case .reservoirEmpty:
            return LocalizedString("Reservoir empty", comment: "Patch state for reservoirEmpty")
        case .baseFault,
             .patchFault,
             .patchFaultd2:
            return LocalizedString("Fault", comment: "Patch state for patchFault, patchFaultd2, baseFault")
        case .batteryOut:
            return LocalizedString("Battery empty", comment: "Patch state for batteryOut")
        case .noCalibration:
            return LocalizedString("No calibration", comment: "Patch state for noCalibration")
        case .stopped:
            return LocalizedString("Stopped", comment: "Patch state for stopped")
        }
    }
}
