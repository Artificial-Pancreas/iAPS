import CGMBLEKit
import Foundation
import G7SensorKit
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

    static func cgmExpirationByPluginIdentifier(_ cgmManager: CGMManager?) -> TimeInterval? {
        guard let cgmManager else { return nil }
        let secondsOfDay = 8.64E4

        return switch cgmManager.pluginIdentifier {
        case G6CGMManager.pluginIdentifier: 10 * secondsOfDay
        case G7CGMManager.pluginIdentifier: 10.5 * secondsOfDay
        case LibreTransmitterManagerV3.pluginIdentifier: libreExpirationSeconds
        case MinimedPumpManager.pluginIdentifier: 6 * secondsOfDay
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
        case G5CGMManager.pluginIdentifier: return CGMType.dexcomG5.rawValue
        case G6CGMManager.pluginIdentifier: return CGMType.dexcomG6.rawValue
        case G7CGMManager.pluginIdentifier: return CGMType.dexcomG7.rawValue
        case LibreTransmitterManagerV3.pluginIdentifier: return CGMType.libreTransmitter.rawValue
        case NightscoutRemoteCGM.pluginIdentifier: return CGMType.nightscout.rawValue
        case MockCGMManager.pluginIdentifier: return CGMType.simulator.rawValue
        case MinimedPumpManager.pluginIdentifier: return CGMType.enlite.rawValue
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
            if let activatedAt = (pumpManager as? OmniPumpManager)?.state.podState?.activatedAt {
                return activatedAt
            }
            // Plugin dual-load can make `as? OmniPumpManager` fail; read serializable state instead.
            return omniPodState(from: pumpManager)?["activatedAt"] as? Date
        default:
            if pumpManager.pluginIdentifier.hasPrefix("Omni") {
                return omniPodState(from: pumpManager)?["activatedAt"] as? Date
            }
            return nil
        }
    }

    static func pumpExpirationDate(_ pumpManager: PumpManager) -> Date? {
        switch pumpManager.pluginIdentifier {
        case MedtrumPumpManager.pluginIdentifier:
            return (pumpManager as? MedtrumPumpManager)?.state.patchExpiresAt
        case OmniPumpManager.pluginIdentifier:
            if let expiresAt = (pumpManager as? OmniPumpManager)?.state.podState?.expiresAt {
                return expiresAt
            }
            // Plugin dual-load can make `as? OmniPumpManager` fail; read serializable state instead.
            return omniPodState(from: pumpManager)?["expiresAt"] as? Date
        default:
            if pumpManager.pluginIdentifier.hasPrefix("Omni") {
                return omniPodState(from: pumpManager)?["expiresAt"] as? Date
            }
            return nil
        }
    }

    static func pumpReservoir(_ pumpManager: PumpManager) -> Decimal? {
        switch pumpManager.pluginIdentifier {
        case OmniPumpManager.pluginIdentifier:
            if let omni = pumpManager as? OmniPumpManager {
                let reservoirVal = omni.state.podState?.lastInsulinMeasurements?.reservoirLevel ?? 0xDEAD_BEEF
                let reservoir = Decimal(reservoirVal) > 50.0 ? 0xDEAD_BEEF : reservoirVal
                return Decimal(reservoir)
            }
            return omniReservoir(from: pumpManager)
        case MedtrumPumpManager.pluginIdentifier:
            guard let reservoir = (pumpManager as? MedtrumPumpManager)?.state.reservoir else { return nil }
            return Decimal(reservoir)
        default:
            if pumpManager.pluginIdentifier.hasPrefix("Omni") {
                return omniReservoir(from: pumpManager)
            }
            return nil
        }
    }

    /// OmnipodKit may be loaded from the plugin bundle while FreeAPS also imports the module.
    /// Prefer typed access when the cast works; otherwise parse `rawState`.
    private static func omniPodState(from pumpManager: PumpManager) -> [String: Any]? {
        pumpManager.rawState["podState"] as? [String: Any]
    }

    private static func omniReservoir(from pumpManager: PumpManager) -> Decimal? {
        let measurements = omniPodState(from: pumpManager)?["lastInsulinMeasurements"] as? [String: Any]
        let reservoirVal = (measurements?["reservoirLevel"] as? Double) ?? 0xDEAD_BEEF
        let reservoir = Decimal(reservoirVal) > 50.0 ? 0xDEAD_BEEF : Decimal(reservoirVal)
        return reservoir
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
