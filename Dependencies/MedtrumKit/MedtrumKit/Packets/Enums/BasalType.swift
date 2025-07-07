enum BasalType: UInt8, Codable {
    case NONE
    case STANDARD
    case EXERCISE
    case HOLIDAY
    case PROGRAM_A
    case PROGRAM_B
    case ABSOLUTE_TEMP
    case RELATIVE_TEMP
    case PROGRAM_C
    case PROGRAM_D
    case SICK
    case AUTO
    case NEW
    case SUSPEND_LOW_GLUCOSE
    case SUSPEND_PREDICT_LOW_GLUCOSE
    case SUSPEND_AUTO
    case SUSPEND_MORE_THAN_MAX_PER_HOUR
    case SUSPEND_MORE_THAN_MAX_PER_DAY
    case SUSPEND_MANUAL
    case SUSPEND_KEY_LOST
    case STOP_OCCLUSION
    case STOP_EXPIRED
    case STOP_EMPTY
    case STOP_PATCH_FAULT
    case STOP_PATCH_FAULT2
    case STOP_BASE_FAULT
    case STOP_DISCARD
    case STOP_BATTERY_EMPTY
    case STOP
    case PAUSE_INTERRUPT
    case PRIME
    case AUTO_MODE_START
    case AUTO_MODE_EXIT
    case AUTO_MODE_TARGET_100
    case AUTO_MODE_TARGET_110
    case AUTO_MODE_TARGET_120
    case AUTO_MODE_BREAKFAST
    case AUTO_MODE_LUNCH
    case AUTO_MODE_DINNER
    case AUTO_MODE_SNACK
    case AUTO_MODE_EXERCISE_START
    case AUTO_MODE_EXERCISE_EXIT

    func isTempBasal() -> Bool {
        switch self {
        case .ABSOLUTE_TEMP,
             .RELATIVE_TEMP:
            return true
        default:
            return false
        }
    }

    func isSuspendedByPump() -> Bool {
        switch self {
        case .STOP,
             .STOP_BASE_FAULT,
             .STOP_BATTERY_EMPTY,
             .STOP_DISCARD,
             .STOP_EMPTY,
             .STOP_EXPIRED,
             .STOP_OCCLUSION,
             .STOP_PATCH_FAULT,
             .STOP_PATCH_FAULT2,
             .SUSPEND_AUTO,
             .SUSPEND_KEY_LOST,
             .SUSPEND_LOW_GLUCOSE,
             .SUSPEND_MANUAL,
             .SUSPEND_MORE_THAN_MAX_PER_DAY,
             .SUSPEND_MORE_THAN_MAX_PER_HOUR,
             .SUSPEND_PREDICT_LOW_GLUCOSE:
            return true
        default:
            return false
        }
    }
}
