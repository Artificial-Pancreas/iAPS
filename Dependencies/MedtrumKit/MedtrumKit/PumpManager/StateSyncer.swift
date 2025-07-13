import LoopKit

func syncState(
    syncResponse: SynchronizePacketResponse,
    state: MedtrumPumpState,
    delegate: (any PumpManagerDelegate)?,
    pumpManager: MedtrumPumpManager
) {
    state.pumpState = syncResponse.state

    if let reservoir = syncResponse.reservoir {
        state.reservoir = reservoir
        delegate?.pumpManager(pumpManager, didReadReservoirValue: state.reservoir, at: Date.now) { _ in }
    }

    if let basal = syncResponse.basal {
        switch basal.type {
        case .ABSOLUTE_TEMP,
             .RELATIVE_TEMP:
            state.basalState = .tempBasal
            state.tempBasalUnits = basal.rate

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
            state.basalState = .suspended

        default:
            state.basalState = .active
            state.tempBasalUnits = nil
            state.tempBasalDuration = nil
        }
    }

    if let battery = syncResponse.battery {
        state.battery = battery.voltageB
    }

    if let prime = syncResponse.primeProgress {
        state.primeProgress = prime
    }

    if let startTime = syncResponse.startTime {
        state.patchActivatedAt = startTime
        state.patchExpiresAt = state.patchActivatedAt.addingTimeInterval(.days(3)).addingTimeInterval(.hours(8))
    }

    if let storage = syncResponse.storage {
        state.patchId = UInt64(storage.patchId).toData(length: 4)
    }

    state.lastSync = Date.now
}
