enum AlarmState: UInt16, Codable {
    case None = 0
    case PumpLowBattery = 1 // Mapped from error flag 1
    case PumpLowReservoir = 2 // Mapped from error flag
    case PumpExpiresSoon = 4 // Mapped from error flag 3
    case LowBgSuspended // Mapped from pump status 64
    case LowBgSuspended2 // Mapped from pump status 65
    case AutoSuspended // Mapped from pump status 66
    case HourlyMaxSuspended // Mapped from pump status 67
    case DailyMaxSuspended // Mapped from pump status 68
    case Suspended // Mapped from pump status 69
    case Paused // Mapped from pump status 70
    case Occlusion // Mapped from pump status 96
    case Expired // Mapped from pump status 97
    case ReservoirEmpty // Mapped from pump status 98
    case PatchFault // Mapped from pump status 99
    case PatchFault2 // Mapped from pump status 100
    case BaseFault // Mapped from pump status 101
    case BatteryOut // Mapped from pump status 102
    case NoCalibration // Mapped from pump status 103
}
