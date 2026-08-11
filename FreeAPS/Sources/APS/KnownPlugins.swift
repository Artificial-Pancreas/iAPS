import CGMBLEKit
import EversenseKit
import Foundation
import G7SensorKit
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
        cgmManager.pluginIdentifier == LibreTransmitterManagerV3.pluginIdentifier
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
        case G7CGMManager.pluginIdentifier: 10.5 * secondsOfDay
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

    static func pumpExpirationDate(_ pumpManager: PumpManager) -> Date? {
        switch pumpManager.pluginIdentifier {
        case MedtrumPumpManager.pluginIdentifier:
            return (pumpManager as? MedtrumPumpManager)?.state.patchExpiresAt
        case OmniPumpManager.pluginIdentifier:
            return (pumpManager as? OmniPumpManager)?.state.podState?.expiresAt
        default: return nil
        }
    }

    static func pumpReservoir(_ pumpManager: PumpManager) -> Decimal? {
        switch pumpManager.pluginIdentifier {
        case OmniPumpManager.pluginIdentifier:
            let reservoirVal = (pumpManager as? OmniPumpManager)?.state.podState?.lastInsulinMeasurements?
                .reservoirLevel ?? 0xDEAD_BEEF
            let reservoir = Decimal(reservoirVal) > 50.0 ? 0xDEAD_BEEF : reservoirVal
            return Decimal(reservoir)
        case MedtrumPumpManager.pluginIdentifier:
            guard let reservoir = (pumpManager as? MedtrumPumpManager)?.state.reservoir else { return nil }
            return Decimal(reservoir)
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
}

struct GlucoseSourceInfo {
    let description: String?
    let transmitterBattery: Double?
}
