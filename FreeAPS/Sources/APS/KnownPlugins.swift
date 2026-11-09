import CGMBLEKit
import DanaKit
import EversenseKit
import Foundation
import G7SensorKit
import HealthKit
import LibreLoop
import LibreTransmitter
import LoopKit
import MedtrumKit
import MinimedKit
import MockKit
import NightscoutRemoteCGM
import OmnipodKit

enum KnownPlugins {
    static func allowCalibrations(for cgmManager: CGMManager) -> Bool {
        cgmManager.pluginIdentifier == LibreTransmitterManagerV3.pluginIdentifier ||
            cgmManager.pluginIdentifier == LibreLoopCGMManager.pluginIdentifier ||
            cgmManager.pluginIdentifier == G6CGMManager.pluginIdentifier ||
            cgmManager.pluginIdentifier == G7CGMManager.pluginIdentifier ||
            cgmManager.pluginIdentifier == EversenseCGMManager.pluginIdentifier
    }

    static func glucoseUploadingAvailable(for cgmManager: CGMManager) -> Bool {
        switch cgmManager.pluginIdentifier {
        case MockCGMManager.pluginIdentifier: return false
        case NightscoutRemoteCGM.pluginIdentifier: return false
        default: return true
        }
    }

    private static let secondsOfDay = 8.64E4

    static func cgmExpirationByPluginIdentifier(_ cgmManager: CGMManager?) -> TimeInterval? {
        guard let cgmManager else { return nil }

        return switch cgmManager.pluginIdentifier {
        case G6CGMManager.pluginIdentifier: 10 * secondsOfDay
        case G7CGMManager.pluginIdentifier: g7SessionSpan(cgmManager as? G7CGMManager)
        case LibreTransmitterManagerV3.pluginIdentifier: libreExpirationSeconds
        case LibreLoopCGMManager.pluginIdentifier:
            (cgmManager as? LibreLoopCGMManager)?.state.wearDurationMinutes.map { TimeInterval($0) * 60 }
                ?? LibreLoopSensorLifecycle.activeDuration
        case MinimedPumpManager.pluginIdentifier: 6 * secondsOfDay
        case EversenseCGMManager
            .pluginIdentifier: (((cgmManager as? EversenseCGMManager)?.state.is365 ?? false) ? 365 : 180) * secondsOfDay
        default: nil
        }
    }

    static var libreExpirationSeconds: TimeInterval? {
        guard let maxAge = UserDefaults.standard.preSelectedSensor?.maxAge, maxAge > 0 else {
            return nil
        }
        return TimeInterval(maxAge * 60) // Convert minutes to seconds
    }

    /// Time from `sessionStart` (end of warm-up for the G7) to the driver's `sensorEndsAt`, so the Home
    /// countdown reaches zero when the sensor stops. The session length (10 or 15 days, 12 h grace
    /// included) is only known once the sensor has connected; the G7 defaults apply until then.
    private static func g7SessionSpan(_ manager: G7CGMManager?) -> TimeInterval {
        let lifetime = manager?.lifetime ?? G7Sensor.defaultLifetime
        let warmup = manager?.warmupDuration ?? G7Sensor.defaultWarmupDuration
        return lifetime + G7Sensor.gracePeriod - warmup
    }

    static func sessionStart(cgmManager: CGMManager) -> Date? {
        switch cgmManager.pluginIdentifier {
        case G5CGMManager.pluginIdentifier:
            return (cgmManager as? G5CGMManager)?.latestReading?.sessionStartDate
        case G6CGMManager.pluginIdentifier:
            return (cgmManager as? G6CGMManager)?.latestReading?.sessionStartDate
        case G7CGMManager.pluginIdentifier:
            return (cgmManager as? G7CGMManager)?.sensorFinishesWarmupAt
        case LibreTransmitterManagerV3.pluginIdentifier:
            return (cgmManager as? LibreTransmitterManagerV3)?.sensorInfoObservable.activatedAt
        case LibreLoopCGMManager.pluginIdentifier:
            return (cgmManager as? LibreLoopCGMManager)?.state.activatedAt
        case EversenseCGMManager.pluginIdentifier:
            return (cgmManager as? EversenseCGMManager)?.state.activatedAt
        default:
            return nil
        }
    }

    /// The sensor's serial where the manager holds it; nil otherwise (and while unknown). Not the Dexcom G5/G6
    /// transmitter's id: a transmitter outlives sensors. The CGM sessions only (`CGMSessionStore`).
    static func sensorId(cgmManager: CGMManager) -> String? {
        let id: String? = switch cgmManager.pluginIdentifier {
        case G7CGMManager.pluginIdentifier: (cgmManager as? G7CGMManager)?.sensorName
        case LibreTransmitterManagerV3.pluginIdentifier: (cgmManager as? LibreTransmitterManagerV3)?.sensorInfoObservable
            .sensorSerial
        case LibreLoopCGMManager.pluginIdentifier: (cgmManager as? LibreLoopCGMManager)?.state.sensorSerial
        default: nil
        }
        // LibreTransmitter's placeholders before a sensor reads
        guard let id, !id.isEmpty, id != "-" else { return nil }
        return id
    }

    /// The `device` of the readings iAPS uploads to Nightscout (`nightscoutDevice(_:plugin:sensorId:title:)`) for this
    /// manager: its sensor's serial (`sensorId`), and as the title an AppGroup CGM's source app, else the manager's.
    static func nightscoutDevice(_ device: HKDevice?, cgmManager: CGMManager) -> String? {
        var title = cgmManager.localizedTitle
        if let source = (cgmManager as? AppGroupCGM)?.appGroupSource,
           let app = source.latestReadingFrom?.displayName ?? source.latestReadingFromOther
        {
            title = app
        }
        return nightscoutDevice(
            device,
            plugin: cgmManager.pluginIdentifier,
            sensorId: sensorId(cgmManager: cgmManager),
            title: title
        )
    }

    /// The `device` of the readings iAPS uploads to Nightscout (`NightscoutCGMDevice.format`): Loop's
    /// "<manufacturer> <model> <id>" from a reading's (or the manager's) `HKDevice`. Firmware and battery stay out, and
    /// so does anything that changes within a sensor, so Nightscout's delta doesn't split by device:
    /// - the G7: the reading's own sensor name (a batch can carry the previous sensor's readings), else the manager's;
    /// - LibreLoop: "Abbott Libre 3 <the reading's serial>", always: its model and name say "Libre 3 Plus" only once
    ///   the sensor's generation is known;
    /// - LibreTransmitter: "Abbott LibreTransmitter <the sensor's serial>", always: its `HKDevice` names the bridge
    ///   ("MiaomiaoClient", the bridge's maker once it connects) and no sensor;
    /// - the others (the G5/G6: the transmitter's id is the name): the device as it is, with `sensorId`.
    /// Without an `HKDevice`: `title`.
    static func nightscoutDevice(_ device: HKDevice?, plugin: String, sensorId: String?, title: String?) -> String? {
        switch plugin {
        case G7CGMManager.pluginIdentifier:
            return NightscoutCGMDevice.format(
                device,
                sensorId: NightscoutCGMDevice.clean(device?.name) ?? sensorId,
                title: title
            )
        case LibreLoopCGMManager.pluginIdentifier:
            return NightscoutCGMDevice.format(
                Self.stableDevice(product: "Libre 3"),
                sensorId: NightscoutCGMDevice.clean(device?.localIdentifier) ?? sensorId,
                title: title
            )
        case LibreTransmitterManagerV3.pluginIdentifier:
            return NightscoutCGMDevice.format(
                Self.stableDevice(product: "LibreTransmitter"),
                sensorId: sensorId,
                title: title
            )
        default:
            return NightscoutCGMDevice.format(device, sensorId: sensorId, title: title)
        }
    }

    /// An Abbott sensor's device with only a fixed product: the same string for every reading of a sensor.
    private static func stableDevice(product: String) -> HKDevice {
        HKDevice(
            name: product,
            manufacturer: "Abbott",
            model: nil,
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
    }

    /// A `.sensorStart` event's sensor id: its device identifier, but nil for the Dexcom G5/G6 (the transmitter's).
    static func sensorId(of event: PersistedCgmEvent, cgmManager: CGMManager?) -> String? {
        let plugin = cgmManager?.pluginIdentifier
        guard plugin != G5CGMManager.pluginIdentifier, plugin != G6CGMManager.pluginIdentifier,
              !event.deviceIdentifier.isEmpty
        else { return nil }
        return event.deviceIdentifier
    }

    static func appURLByPluginIdentifier(pluginIdentifier: String) -> URL? {
        switch pluginIdentifier {
        case G5CGMManager.pluginIdentifier:
            URL(string: "dexcomgcgm://")!
        case G6CGMManager.pluginIdentifier:
            URL(string: "dexcomg6://")!
        case G7CGMManager.pluginIdentifier:
            URL(string: "dexcomg7://")!
        default: nil
        }
    }

    static func cgmIdForStatistics(for cgmManager: CGMManager?) -> String? {
        guard let cgmManager else { return nil }

        switch cgmManager.pluginIdentifier {
        case G5CGMManager.pluginIdentifier: return "dexcomG5"
        case G6CGMManager.pluginIdentifier: return "dexcomG6"
        case G7CGMManager.pluginIdentifier: return "dexcomG7"
        case EversenseCGMManager.pluginIdentifier: return "eversense"
        case LibreTransmitterManagerV3.pluginIdentifier: return "libreTransmitter"
        case LibreLoopCGMManager.pluginIdentifier: return "libre3"
        case NightscoutRemoteCGM.pluginIdentifier: return "nightscout"
        case MockCGMManager.pluginIdentifier: return "simulator"
        case MinimedPumpManager.pluginIdentifier: return "enlite"
        case AppGroupCGM.pluginIdentifier:
            guard let cgmManager = cgmManager as? AppGroupCGM else {
                return nil
            }
            return cgmManager.appGroupSource.latestReadingFrom?.rawValue ??
                cgmManager.appGroupSource.latestReadingFromOther
        default: return cgmManager.pluginIdentifier
        }
    }

    static func isManualTempBasalActive(_ pumpManager: PumpManager) -> Bool? {
        guard case let .tempBasal(dose) = pumpManager.status.basalDeliveryState else { return false }
        return !(dose.automatic ?? true)
    }

    static func pumpActivationDate(_ pumpManager: PumpManager) -> Date? {
        switch pumpManager.pluginIdentifier {
        case MedtrumPumpManager.pluginIdentifier:
            return (pumpManager as? MedtrumPumpManager)?.state.patchActivatedAt
        case OmniPumpManager.pluginIdentifier:
            return (pumpManager as? OmniPumpManager)?.state.podState?.activatedAt
        default: return nil
        }
    }

    /// The pump delivers: onboarded, with an active delivery unit (`isDeliveryUnitActive`, published as
    /// `deliveryUnitActive`).
    static func hasActiveDeliveryUnit(_ info: PumpDisplayInfo) -> Bool {
        info.isOnboarded && info.deliveryUnitActive
    }

    /// The pod or patch can deliver: activated and not faulted, expired or stopped. True for the pumps without the
    /// concept. Only public state of the pump managers.
    static func isDeliveryUnitActive(_ pumpManager: PumpManager) -> Bool {
        switch pumpManager.pluginIdentifier {
        case MedtrumPumpManager.pluginIdentifier:
            guard let state = (pumpManager as? MedtrumPumpManager)?.state, state.patchActivatedAt != nil else {
                return false
            }
            return isDelivering(patchState: state.pumpState.rawValue)
        case OmniPumpManager.pluginIdentifier:
            return isDelivering(
                podActivatedAt: (pumpManager as? OmniPumpManager)?.state.podState?.activatedAt,
                basalDeliveryState: pumpManager.status.basalDeliveryState
            )
        default:
            return true
        }
    }

    /// A Medtrum patch state that delivers, or is suspended (MedtrumKit reports those suspensions as events). Not: the
    /// setup states, the faults (occlusion, reservoir empty, patch/base fault, battery out, no calibration), expired,
    /// stopped.
    static func isDelivering(patchState rawValue: UInt8) -> Bool {
        switch PatchState(rawValue: rawValue) {
        case .active,
             .active_alt,
             .autoSuspended,
             .dailyMaxSuspended,
             .hourlyMaxSuspended,
             .lowBgSuspended,
             .lowBgSuspended2,
             .paused,
             .suspended:
            return true
        default:
            return false
        }
    }

    /// An Omnipod pod that delivers: activated, and not faulted. OmniPumpManager reports a faulted pod (or one not set
    /// up) "just like no pod", as `.active(.distantPast)`; its `activatedAt` survives a fault, and no suspend is
    /// reported for it. (`PodState.fault` / `isFaulted` are internal to OmnipodKit.)
    static func isDelivering(
        podActivatedAt: Date?,
        basalDeliveryState: PumpManagerStatus.BasalDeliveryState?
    ) -> Bool {
        guard podActivatedAt != nil else { return false }
        if case let .active(since) = basalDeliveryState, since == .distantPast {
            return false
        }
        return true
    }

    static func pumpExpirationDate(_ pumpManager: PumpManager) -> Date? {
        switch pumpManager.pluginIdentifier {
        case MedtrumPumpManager.pluginIdentifier:
            return (pumpManager as? MedtrumPumpManager)?.state.patchExpiresAt
        case OmniPumpManager.pluginIdentifier:
            return (pumpManager as? OmniPumpManager)?.state.podState?.expiresAt
        default: return nil
        }
    }

    static func pumpReservoir(_ pumpManager: PumpManager) -> ReservoirReading? {
        switch pumpManager.pluginIdentifier {
        case OmniPumpManager.pluginIdentifier:
            if let reservoirVal = (pumpManager as? OmniPumpManager)?.state.podState?.lastInsulinMeasurements?.reservoirLevel,
               reservoirVal <= 50
            {
                return .units(Decimal(reservoirVal))
            } else {
                return .aboveThreshold
            }
        case MedtrumPumpManager.pluginIdentifier:
            guard let reservoir = (pumpManager as? MedtrumPumpManager)?.state.reservoir else { return nil }
            return .units(Decimal(reservoir))
        case DanaKitPumpManager.pluginIdentifier:
            guard let reservoir = (pumpManager as? DanaKitPumpManager)?.state.reservoirLevel else { return nil }
            return .units(Decimal(reservoir))
        case MockPumpManager.pluginIdentifier:
            guard let reservoir = (pumpManager as? MockPumpManager)?.state.reservoirUnitsRemaining else { return nil }
            return .units(Decimal(reservoir))
        default: return nil
        }
    }

    static func cgmInfo(for cgmManager: CGMManager) -> GlucoseSourceInfo? {
        switch cgmManager.pluginIdentifier {
        case G5CGMManager.pluginIdentifier:
            guard let cgmManager = cgmManager as? G5CGMManager else { return nil }
            let description = "Dexcom tramsmitter ID: \(cgmManager.transmitter.ID)"
            return GlucoseSourceInfo(description: description, transmitterBattery: nil)

        case G6CGMManager.pluginIdentifier:
            guard let cgmManager = cgmManager as? G6CGMManager else { return nil }
            let description = "Dexcom tramsmitter ID: \(cgmManager.transmitter.ID)"
            return GlucoseSourceInfo(description: description, transmitterBattery: nil)

        case LibreTransmitterManagerV3.pluginIdentifier:
            guard let cgmManager = cgmManager as? LibreTransmitterManagerV3,
                  let batteryLevel = cgmManager.batteryLevel else { return nil }
            return GlucoseSourceInfo(description: nil, transmitterBattery: batteryLevel)

        case AppGroupCGM.pluginIdentifier:
            var description = "Group ID: \(Bundle.main.appGroupSuiteName ?? "Not set")"
            if let cgmManager = cgmManager as? AppGroupCGM,
               let app = cgmManager.appGroupSource.latestReadingFrom?.displayName ?? cgmManager.appGroupSource
               .latestReadingFromOther
            {
                description = "\(description), app: \(app)"
            }
            return GlucoseSourceInfo(description: description, transmitterBattery: nil)

        default: return nil
        }
    }

    static func isOneMinuteReadingsEnabled(for cgmManager: CGMManager) -> Bool {
        switch cgmManager.pluginIdentifier {
        case LibreTransmitterManagerV3.pluginIdentifier:
            return (cgmManager as? LibreTransmitterManagerV3)?.allowOneMinuteReadings ?? false
        case LibreLoopCGMManager.pluginIdentifier:
            return (cgmManager as? LibreLoopCGMManager)?.state.experimentalMinuteByMinuteForwarding ?? false
        default: return false
        }
    }

    static func pumpModel(_ pumpManager: PumpManager) -> String? {
        switch pumpManager.pluginIdentifier {
        case MinimedPumpManager.pluginIdentifier:
            return (pumpManager as? MinimedPumpManager)?.state.pumpModel.rawValue
        default: return nil
        }
    }
}

struct GlucoseSourceInfo {
    let description: String?
    let transmitterBattery: Double?
}
