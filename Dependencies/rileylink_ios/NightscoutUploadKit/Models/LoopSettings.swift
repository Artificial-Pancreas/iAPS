//
//  LoopSettings.swift
//  NightscoutUploadKit
//
//  Created by Pete Schwamb on 4/21/20.
//  Copyright © 2020 Pete Schwamb. All rights reserved.
//
import Foundation

public struct LoopSettings {
    typealias RawValue = [String: Any]
    
    public let dosingEnabled: Bool
    public let overridePresets: [TemporaryScheduleOverride]
    public let scheduleOverride: TemporaryScheduleOverride?
    public let minimumBGGuard: Double?
    public let preMealTargetRange: ClosedRange<Double>?
    public let maximumBasalRatePerHour: Double?
    public let maximumBolus: Double?
    public let deviceToken: String?
    public let bundleIdentifier: String?
    public let dosingStrategy: String?

    public init(dosingEnabled: Bool, overridePresets: [TemporaryScheduleOverride], scheduleOverride: TemporaryScheduleOverride?, minimumBGGuard: Double?, preMealTargetRange: ClosedRange<Double>?, maximumBasalRatePerHour: Double?, maximumBolus: Double?,
                deviceToken: String?, bundleIdentifier: String?, dosingStrategy: String?) {
        self.dosingEnabled = dosingEnabled
        self.overridePresets = overridePresets
        self.scheduleOverride = scheduleOverride
        self.minimumBGGuard = minimumBGGuard
        self.preMealTargetRange = preMealTargetRange
        self.maximumBasalRatePerHour = maximumBasalRatePerHour
        self.maximumBolus = maximumBolus
        self.deviceToken = deviceToken
        self.bundleIdentifier = bundleIdentifier
        self.dosingStrategy = dosingStrategy
    }

    public var dictionaryRepresentation: [String: Any] {

        var rval: [String: Any] = [
            "dosingEnabled": dosingEnabled,
            "overridePresets": overridePresets.map { $0.dictionaryRepresentation },
        ]

        rval["minimumBGGuard"] = minimumBGGuard
        rval["scheduleOverride"] = scheduleOverride?.dictionaryRepresentation

        if let preMealTargetRange = preMealTargetRange {
            rval["preMealTargetRange"] = [preMealTargetRange.lowerBound, preMealTargetRange.upperBound]
        }

        rval["maximumBasalRatePerHour"] = maximumBasalRatePerHour
        rval["maximumBolus"] = maximumBolus
        rval["deviceToken"] = deviceToken
        rval["dosingStrategy"] = dosingStrategy

        if let bundleIdentifier = bundleIdentifier {
            rval["bundleIdentifier"] = bundleIdentifier
        }

        return rval
    }

    init?(rawValue: RawValue) {
        guard
            let dosingEnabled = rawValue["dosingEnabled"] as? Bool,
            let overridePresetsRaw = rawValue["overridePresets"] as? [TemporaryScheduleOverride.RawValue]
        else {
            return nil
        }

        self.dosingEnabled = dosingEnabled
        self.overridePresets = overridePresetsRaw.compactMap { TemporaryScheduleOverride(rawValue: $0) }

        if let scheduleOverrideRaw = rawValue["scheduleOverride"] as? TemporaryScheduleOverride.RawValue {
            scheduleOverride = TemporaryScheduleOverride(rawValue: scheduleOverrideRaw)
        } else {
            scheduleOverride = nil
        }

        minimumBGGuard = rawValue["minimumBGGuard"] as? Double

        if let preMealTargetRangeRaw = rawValue["preMealTargetRange"] as? [Double], preMealTargetRangeRaw.count == 2 {
            preMealTargetRange = ClosedRange(uncheckedBounds: (lower: preMealTargetRangeRaw[0], upper: preMealTargetRangeRaw[1]))
        } else {
            preMealTargetRange = nil
        }

        maximumBasalRatePerHour = rawValue["maximumBasalRatePerHour"] as? Double
        maximumBolus = rawValue["maximumBolus"] as? Double
        deviceToken = rawValue["deviceToken"] as? String
        bundleIdentifier = rawValue["bundleIdentifier"] as? String
        dosingStrategy = rawValue["dosingStrategy"] as? String
     }
}
