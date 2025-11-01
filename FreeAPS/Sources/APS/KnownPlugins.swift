import CGMBLEKit
import Foundation
import G7SensorKit
import LibreTransmitter
import LoopKit
import MedtrumKit
import MinimedKit
import MockKit
import NightscoutRemoteCGM
import OmniBLE
import OmniKit

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
        case LibreTransmitterManagerV3.pluginIdentifier: 14.5 * secondsOfDay
        case MinimedPumpManager.pluginIdentifier: 6 * secondsOfDay
        default: nil
        }
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
        switch pumpManager.pluginIdentifier {
        case OmnipodPumpManager.pluginIdentifier:
            if let omnipod = pumpManager as? OmnipodPumpManager,
               let tempBasal = omnipod.state.podState?.unfinalizedTempBasal,
               !tempBasal.isFinished(),
               !tempBasal.automatic
            {
                return true
            } else {
                return false
            }
        case OmniBLEPumpManager.pluginIdentifier:
            if let omnipodBLE = pumpManager as? OmniBLEPumpManager,
               let tempBasal = omnipodBLE.state.podState?.unfinalizedTempBasal,
               !tempBasal.isFinished(),
               !tempBasal.automatic
            {
                return true
            } else {
                return false
            }
        default: return nil
        }
    }

    static func pumpActivationDate(_ pumpManager: PumpManager) -> Date? {
        switch pumpManager.pluginIdentifier {
        case OmnipodPumpManager.pluginIdentifier:
            return (pumpManager as? OmnipodPumpManager)?.state.podState?.activatedAt
        case OmniBLEPumpManager.pluginIdentifier:
            return (pumpManager as? OmniBLEPumpManager)?.state.podState?.activatedAt
        case MedtrumPumpManager.pluginIdentifier:
            return (pumpManager as? MedtrumPumpManager)?.state.patchActivatedAt
        default: return nil
        }
    }

    static func pumpExpirationDate(_ pumpManager: PumpManager) -> Date? {
        switch pumpManager.pluginIdentifier {
        case OmnipodPumpManager.pluginIdentifier:
            return (pumpManager as? OmnipodPumpManager)?.state.podState?.expiresAt
        case OmniBLEPumpManager.pluginIdentifier:
            return (pumpManager as? OmniBLEPumpManager)?.state.podState?.expiresAt
        case MedtrumPumpManager.pluginIdentifier:
            return (pumpManager as? MedtrumPumpManager)?.state.patchExpiresAt
        default: return nil
        }
    }

    static func pumpReservoir(_ pumpManager: PumpManager) -> Decimal? {
        switch pumpManager.pluginIdentifier {
        case OmnipodPumpManager.pluginIdentifier:
            let reservoirVal = (pumpManager as? OmnipodPumpManager)?.state.podState?.lastInsulinMeasurements?
                .reservoirLevel ?? 0xDEAD_BEEF
            // TODO: find the value Pod.maximumReservoirReading
            let reservoir = Decimal(reservoirVal) > 50.0 ? 0xDEAD_BEEF : reservoirVal
            return Decimal(reservoir)
        case OmniBLEPumpManager.pluginIdentifier:
            let reservoirVal = (pumpManager as? OmniBLEPumpManager)?.state.podState?.lastInsulinMeasurements?
                .reservoirLevel ?? 0xDEAD_BEEF
            // TODO: find the value Pod.maximumReservoirReading
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
