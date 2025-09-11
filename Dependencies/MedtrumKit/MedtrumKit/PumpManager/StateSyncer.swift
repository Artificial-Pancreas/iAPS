import LoopKit

enum StateSyncer {
    static func sync(
        syncResponse: SynchronizePacketResponse,
        state: MedtrumPumpState,
        delegate: (any PumpManagerDelegate)?,
        pumpManager: MedtrumPumpManager
    ) {
        StateSyncer.updatePumpState(syncResponse: syncResponse, state: state, delegate: delegate)

        if let reservoir = syncResponse.reservoir {
            state.reservoir = reservoir
            delegate?.pumpManager(pumpManager, didReadReservoirValue: state.reservoir.rounded(toPlaces: 1), at: Date.now) { _ in }
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

        if let prime = syncResponse.primeProgress {
            state.primeProgress = prime
        }

        if let battery = syncResponse.battery {
            state.battery = battery.voltageB
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

    private static func updatePumpState(
        syncResponse: SynchronizePacketResponse,
        state: MedtrumPumpState,
        delegate _: (any PumpManagerDelegate)?
    ) {
        state.pumpState = syncResponse.state

        // Send notification for specific states
        // If this has already been done, iOS will remove the old one
        switch syncResponse.state {
        case .dailyMaxSuspended:
            NotificationManager.patchDailyMaxNotification()
        case .hourlyMaxSuspended:
            NotificationManager.patchHourlyMaxNotification()
        case .occlusion:
            NotificationManager.occlusionNotification()
        case .baseFault,
             .patchFault,
             .patchFaultd2:
            NotificationManager.patchFaultNotification()
        case .reservoirEmpty:
            NotificationManager.reservoirEmptyNotification()
        default:
            break
        }
    }
}
