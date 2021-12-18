//
//  MinimedPumpManagerState.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import LoopKit
import RileyLinkKit
import RileyLinkBLEKit

public struct ReconciledDoseMapping: Equatable {
    let startTime: Date
    let uuid: UUID
    let eventRaw: Data
}

extension ReconciledDoseMapping: RawRepresentable {
    public typealias RawValue = [String:Any]
    
    public init?(rawValue: [String : Any]) {
        guard
            let startTime = rawValue["startTime"] as? Date,
            let uuidString = rawValue["uuid"] as? String,
            let uuid = UUID(uuidString: uuidString),
            let eventRawString = rawValue["eventRaw"] as? String,
            let eventRaw = Data(hexadecimalString: eventRawString) else
        {
            return nil
        }
        self.startTime = startTime
        self.uuid = uuid
        self.eventRaw = eventRaw
    }
    
    public var rawValue: [String : Any] {
        return [
            "startTime": startTime,
            "uuid": uuid.uuidString,
            "eventRaw": eventRaw.hexadecimalString,
        ]
    }
}

public struct MinimedPumpManagerState: RawRepresentable, Equatable {
    public typealias RawValue = PumpManager.RawStateValue

    public static let version = 2

    public var batteryChemistry: BatteryChemistryType

    public var batteryPercentage: Double?

    public var suspendState: SuspendState

    public var lastReservoirReading: ReservoirReading?

    public var lastTuned: Date?  // In-memory only

    public var lastValidFrequency: Measurement<UnitFrequency>?

    public var preferredInsulinDataSource: InsulinDataSource

    public var useMySentry: Bool

    public let pumpColor: PumpColor

    public let pumpModel: PumpModel
    
    public let pumpFirmwareVersion: String

    public let pumpID: String

    public let pumpRegion: PumpRegion

    public var pumpSettings: PumpSettings {
        get {
            return PumpSettings(pumpID: pumpID, pumpRegion: pumpRegion)
        }
    }

    public var pumpState: PumpState {
        get {
            var state = PumpState()
            state.pumpModel = pumpModel
            state.timeZone = timeZone
            state.lastValidFrequency = lastValidFrequency
            state.lastTuned = lastTuned
            state.useMySentry = useMySentry
            return state
        }
        set {
            lastValidFrequency = newValue.lastValidFrequency
            lastTuned = newValue.lastTuned
            timeZone = newValue.timeZone
        }
    }

    public var rileyLinkConnectionManagerState: RileyLinkConnectionManagerState?

    public var timeZone: TimeZone

    public var unfinalizedBolus: UnfinalizedDose?

    public var unfinalizedTempBasal: UnfinalizedDose?

    // Doses we're tracking that haven't shown up in history yet
    public var pendingDoses: [UnfinalizedDose]

    // Maps
    public var reconciliationMappings: [Data:ReconciledDoseMapping]

    public var lastReconciliation: Date?
    
    public var rileyLinkBatteryAlertLevel: Int?
    
    public var lastRileyLinkBatteryAlertDate: Date = .distantPast

    public var insulinType: InsulinType?

    public init(batteryChemistry: BatteryChemistryType = .alkaline, preferredInsulinDataSource: InsulinDataSource = .pumpHistory, useMySentry: Bool = false, pumpColor: PumpColor, pumpID: String, pumpModel: PumpModel, pumpFirmwareVersion: String, pumpRegion: PumpRegion, rileyLinkConnectionManagerState: RileyLinkConnectionManagerState?, timeZone: TimeZone, suspendState: SuspendState, lastValidFrequency: Measurement<UnitFrequency>? = nil, batteryPercentage: Double? = nil, lastReservoirReading: ReservoirReading? = nil, unfinalizedBolus: UnfinalizedDose? = nil, unfinalizedTempBasal: UnfinalizedDose? = nil, pendingDoses: [UnfinalizedDose]? = nil, recentlyReconciledEvents: [Data:ReconciledDoseMapping]? = nil, lastReconciliation: Date? = nil, insulinType: InsulinType? = nil) {
        self.batteryChemistry = batteryChemistry
        self.preferredInsulinDataSource = preferredInsulinDataSource
        self.useMySentry = useMySentry
        self.pumpColor = pumpColor
        self.pumpID = pumpID
        self.pumpModel = pumpModel
        self.pumpFirmwareVersion = pumpFirmwareVersion
        self.pumpRegion = pumpRegion
        self.rileyLinkConnectionManagerState = rileyLinkConnectionManagerState
        self.timeZone = timeZone
        self.suspendState = suspendState
        self.lastValidFrequency = lastValidFrequency
        self.batteryPercentage = batteryPercentage
        self.lastReservoirReading = lastReservoirReading
        self.unfinalizedBolus = unfinalizedBolus
        self.unfinalizedTempBasal = unfinalizedTempBasal
        self.pendingDoses = pendingDoses ?? []
        self.reconciliationMappings = recentlyReconciledEvents ?? [:]
        self.lastReconciliation = lastReconciliation
        self.insulinType = insulinType
    }

    public init?(rawValue: RawValue) {
        guard
            let version = rawValue["version"] as? Int,
            let useMySentry = rawValue["useMySentry"] as? Bool,
            let batteryChemistryRaw = rawValue["batteryChemistry"] as? BatteryChemistryType.RawValue,
            let insulinDataSourceRaw = rawValue["insulinDataSource"] as? InsulinDataSource.RawValue,
            let pumpColorRaw = rawValue["pumpColor"] as? PumpColor.RawValue,
            let pumpID = rawValue["pumpID"] as? String,
            let pumpModelNumber = rawValue["pumpModel"] as? PumpModel.RawValue,
            let pumpRegionRaw = rawValue["pumpRegion"] as? PumpRegion.RawValue,
            let timeZoneSeconds = rawValue["timeZone"] as? Int,

            let batteryChemistry = BatteryChemistryType(rawValue: batteryChemistryRaw),
            let insulinDataSource = InsulinDataSource(rawValue: insulinDataSourceRaw),
            let pumpColor = PumpColor(rawValue: pumpColorRaw),
            let pumpModel = PumpModel(rawValue: pumpModelNumber),
            let pumpRegion = PumpRegion(rawValue: pumpRegionRaw),
            let timeZone = TimeZone(secondsFromGMT: timeZoneSeconds)
        else {
            return nil
        }
        
        var rileyLinkConnectionManagerState: RileyLinkConnectionManagerState? = nil
        
        // Migrate
        if version == 1
        {
            if let oldRileyLinkPumpManagerStateRaw = rawValue["rileyLinkPumpManagerState"] as? [String : Any],
                let connectedPeripheralIDs = oldRileyLinkPumpManagerStateRaw["connectedPeripheralIDs"] as? [String]
            {
                rileyLinkConnectionManagerState = RileyLinkConnectionManagerState(autoConnectIDs: Set(connectedPeripheralIDs))
            }
        } else {
            if let rawState = rawValue["rileyLinkConnectionManagerState"] as? RileyLinkConnectionManagerState.RawValue {
                rileyLinkConnectionManagerState = RileyLinkConnectionManagerState(rawValue: rawState)
            }
        }

        let suspendState: SuspendState
        if let isPumpSuspended = rawValue["isPumpSuspended"] as? Bool {
            // migrate
            if isPumpSuspended {
                suspendState = .suspended(Date())
            } else {
                suspendState = .resumed(Date())
            }
        } else if let rawSuspendState = rawValue["suspendState"] as? SuspendState.RawValue, let storedSuspendState = SuspendState(rawValue: rawSuspendState) {
            suspendState = storedSuspendState
        } else {
            return nil
        }
        
        let lastValidFrequency: Measurement<UnitFrequency>?
        if let frequencyRaw = rawValue["lastValidFrequency"] as? Double {
            lastValidFrequency = Measurement<UnitFrequency>(value: frequencyRaw, unit: .megahertz)
        } else {
            lastValidFrequency = nil
        }
        
        let pumpFirmwareVersion = (rawValue["pumpFirmwareVersion"] as? String) ?? ""
        let batteryPercentage = rawValue["batteryPercentage"] as? Double
        
        let lastReservoirReading: ReservoirReading?
        if let rawLastReservoirReading = rawValue["lastReservoirReading"] as? ReservoirReading.RawValue {
            lastReservoirReading = ReservoirReading(rawValue: rawLastReservoirReading)
        } else {
            lastReservoirReading = nil
        }

        let unfinalizedBolus: UnfinalizedDose?
        if let rawUnfinalizedBolus = rawValue["unfinalizedBolus"] as? UnfinalizedDose.RawValue
        {
            unfinalizedBolus = UnfinalizedDose(rawValue: rawUnfinalizedBolus)
        } else {
            unfinalizedBolus = nil
        }

        let unfinalizedTempBasal: UnfinalizedDose?
        if let rawUnfinalizedTempBasal = rawValue["unfinalizedTempBasal"] as? UnfinalizedDose.RawValue
        {
            unfinalizedTempBasal = UnfinalizedDose(rawValue: rawUnfinalizedTempBasal)
        } else {
            unfinalizedTempBasal = nil
        }

        let pendingDoses: [UnfinalizedDose]
        if let rawPendingDoses = rawValue["pendingDoses"] as? [UnfinalizedDose.RawValue] {
            pendingDoses = rawPendingDoses.compactMap( { UnfinalizedDose(rawValue: $0) } )
        } else {
            pendingDoses = []
        }


        let recentlyReconciledEvents: [Data:ReconciledDoseMapping]
        if let rawRecentlyReconciledEvents = rawValue["recentlyReconciledEvents"] as? [ReconciledDoseMapping.RawValue] {
            let mappings = rawRecentlyReconciledEvents.compactMap { ReconciledDoseMapping(rawValue: $0) }
            recentlyReconciledEvents = Dictionary(mappings.map{ ($0.eventRaw, $0) }, uniquingKeysWith: { (old, new) in new } )
        } else {
            recentlyReconciledEvents = [:]
        }
        
        let lastReconciliation = rawValue["lastReconciliation"] as? Date
        
        let insulinType: InsulinType?
        
        if let rawInsulinType = rawValue["insulinType"] as? InsulinType.RawValue {
            insulinType = InsulinType(rawValue: rawInsulinType)
        } else {
            insulinType = nil
        }
        
        self.init(
            batteryChemistry: batteryChemistry,
            preferredInsulinDataSource: insulinDataSource,
            useMySentry: useMySentry,
            pumpColor: pumpColor,
            pumpID: pumpID,
            pumpModel: pumpModel,
            pumpFirmwareVersion: pumpFirmwareVersion,
            pumpRegion: pumpRegion,
            rileyLinkConnectionManagerState: rileyLinkConnectionManagerState,
            timeZone: timeZone,
            suspendState: suspendState,
            lastValidFrequency: lastValidFrequency,
            batteryPercentage: batteryPercentage,
            lastReservoirReading: lastReservoirReading,
            unfinalizedBolus: unfinalizedBolus,
            unfinalizedTempBasal: unfinalizedTempBasal,
            pendingDoses: pendingDoses,
            recentlyReconciledEvents: recentlyReconciledEvents,
            lastReconciliation: lastReconciliation,
            insulinType: insulinType
        )
    }

    public var rawValue: RawValue {
        var value: [String : Any] = [
            "batteryChemistry": batteryChemistry.rawValue,
            "insulinDataSource": preferredInsulinDataSource.rawValue,
            "pumpColor": pumpColor.rawValue,
            "pumpID": pumpID,
            "pumpModel": pumpModel.rawValue,
            "pumpFirmwareVersion": pumpFirmwareVersion,
            "pumpRegion": pumpRegion.rawValue,
            "timeZone": timeZone.secondsFromGMT(),
            "suspendState": suspendState.rawValue,
            "version": MinimedPumpManagerState.version,
            "pendingDoses": pendingDoses.map { $0.rawValue },
            "recentlyReconciledEvents": reconciliationMappings.values.map { $0.rawValue },
        ]

        value["useMySentry"] = useMySentry
        value["batteryPercentage"] = batteryPercentage
        value["lastReservoirReading"] = lastReservoirReading?.rawValue
        value["lastValidFrequency"] = lastValidFrequency?.converted(to: .megahertz).value
        value["rileyLinkConnectionManagerState"] = rileyLinkConnectionManagerState?.rawValue
        value["unfinalizedBolus"] = unfinalizedBolus?.rawValue
        value["unfinalizedTempBasal"] = unfinalizedTempBasal?.rawValue
        value["lastReconciliation"] = lastReconciliation
        value["rileyLinkBatteryAlertLevel"] = rileyLinkBatteryAlertLevel
        value["lastRileyLinkBatteryAlertDate"] = lastRileyLinkBatteryAlertDate
        value["insulinType"] = insulinType?.rawValue

        return value
    }
}


extension MinimedPumpManagerState {
    static let idleListeningEnabledDefaults: RileyLinkDevice.IdleListeningState = .enabled(timeout: .minutes(4), channel: 0)
}


extension MinimedPumpManagerState: CustomDebugStringConvertible {
    public var debugDescription: String {
        return [
            "## MinimedPumpManagerState",
            "batteryChemistry: \(batteryChemistry)",
            "batteryPercentage: \(String(describing: batteryPercentage))",
            "suspendState: \(suspendState)",
            "lastValidFrequency: \(String(describing: lastValidFrequency))",
            "preferredInsulinDataSource: \(preferredInsulinDataSource)",
            "useMySentry: \(useMySentry)",
            "pumpColor: \(pumpColor)",
            "pumpID: ✔︎",
            "pumpModel: \(pumpModel.rawValue)",
            "pumpFirmwareVersion: \(pumpFirmwareVersion)",
            "pumpRegion: \(pumpRegion)",
            "reservoirUnits: \(String(describing: lastReservoirReading?.units))",
            "reservoirValidAt: \(String(describing: lastReservoirReading?.validAt))",
            "unfinalizedBolus: \(String(describing: unfinalizedBolus))",
            "unfinalizedTempBasal: \(String(describing: unfinalizedTempBasal))",
            "pendingDoses: \(pendingDoses)",
            "timeZone: \(timeZone)",
            "recentlyReconciledEvents: \(reconciliationMappings.values.map { "\($0.eventRaw.hexadecimalString) -> \($0.uuid)" })",
            "lastReconciliation: \(String(describing: lastReconciliation))",
            "rileyLinkBatteryAlertLevel: \(String(describing: rileyLinkBatteryAlertLevel))",
            "lastRileyLinkBatteryAlertDate \(String(describing: lastRileyLinkBatteryAlertDate))",
            "insulinType: \(String(describing: insulinType))",
            String(reflecting: rileyLinkConnectionManagerState),
        ].joined(separator: "\n")
    }
}

public enum SuspendState: Equatable, RawRepresentable {
    public typealias RawValue = [String: Any]

    private enum SuspendStateType: Int {
        case suspend, resume
    }

    case suspended(Date)
    case resumed(Date)

    private var identifier: Int {
        switch self {
        case .suspended:
            return 1
        case .resumed:
            return 2
        }
    }

    public init?(rawValue: RawValue) {
        guard let suspendStateType = rawValue["case"] as? SuspendStateType.RawValue,
            let date = rawValue["date"] as? Date else {
                return nil
        }
        switch SuspendStateType(rawValue: suspendStateType) {
        case .suspend?:
            self = .suspended(date)
        case .resume?:
            self = .resumed(date)
        default:
            return nil
        }
    }

    public var rawValue: RawValue {
        switch self {
        case .suspended(let date):
            return [
                "case": SuspendStateType.suspend.rawValue,
                "date": date
            ]
        case .resumed(let date):
            return [
                "case": SuspendStateType.resume.rawValue,
                "date": date
            ]
        }
    }
}
