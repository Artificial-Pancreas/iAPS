//
//  NightscoutProfile.swift
//  NightscoutUploadKit
//

import Foundation

fileprivate let timeZoneMap = (-18...18).reduce(into: [String: String]()) { (dict, hour) in
    let from = TimeZone(secondsFromGMT: 3600 * hour)!.identifier
    let to = String(format: "ETC/GMT%+d", hour * -1)
    dict[from] = to
}

public class ProfileSet {
    
    public struct ScheduleItem {
        let offset: TimeInterval
        let value: Double
        
        public init(offset: TimeInterval, value: Double) {
            self.offset = offset
            self.value = value
        }
        
        public var dictionaryRepresentation: [String: Any] {
            var rep = [String: Any]()
            let hours = floor(offset.hours)
            let minutes = floor((offset - TimeInterval(hours: hours)).minutes)
            rep["time"] = String(format:"%02i:%02i", Int(hours), Int(minutes))
            rep["value"] = value
            rep["timeAsSeconds"] = Int(offset)
            return rep
        }
    }
    
    public struct Profile {
        let timezone : TimeZone
        let dia : TimeInterval
        let sensitivity : [ScheduleItem]
        let carbratio : [ScheduleItem]
        let basal : [ScheduleItem]
        let targetLow : [ScheduleItem]
        let targetHigh : [ScheduleItem]
        let units: String

        public init(timezone: TimeZone, dia: TimeInterval, sensitivity: [ScheduleItem], carbratio: [ScheduleItem], basal: [ScheduleItem], targetLow: [ScheduleItem], targetHigh: [ScheduleItem], units: String) {
            self.timezone = timezone
            self.dia = dia
            self.sensitivity = sensitivity
            self.carbratio = carbratio
            self.basal = basal
            self.targetLow = targetLow
            self.targetHigh = targetHigh
            self.units = units
        }

        public var dictionaryRepresentation: [String: Any] {
            return [
                "dia": dia.hours,
                "carbs_hr": "0",
                "delay": "0",
                "timezone": timeZoneMap[timezone.identifier] ?? timezone.identifier,
                "target_low": targetLow.map { $0.dictionaryRepresentation },
                "target_high": targetHigh.map { $0.dictionaryRepresentation },
                "sens": sensitivity.map { $0.dictionaryRepresentation },
                "basal": basal.map { $0.dictionaryRepresentation },
                "carbratio": carbratio.map { $0.dictionaryRepresentation },
                ]
        }

    }
    
    let startDate : Date
    let units: String
    let enteredBy: String
    let defaultProfile: String
    let store: [String: Profile]
    let settings: LoopSettings
    
    public init(startDate: Date, units: String, enteredBy: String, defaultProfile: String, store: [String: Profile], settings: LoopSettings) {
        self.startDate = startDate
        self.units = units
        self.enteredBy = enteredBy
        self.defaultProfile = defaultProfile
        self.store = store
        self.settings = settings
    }
    
    public var dictionaryRepresentation: [String: Any] {
        let dateFormatter = DateFormatter.ISO8601DateFormatter()
        let mills = String(format: "%.0f", startDate.timeIntervalSince1970.milliseconds)
        
        let dictProfiles = Dictionary(uniqueKeysWithValues:
            store.map { key, value in (key, value.dictionaryRepresentation) })
        
        let rval : [String: Any] = [
            "defaultProfile": defaultProfile,
            "startDate": dateFormatter.string(from: startDate),
            "mills": mills,
            "units": units,
            "enteredBy": enteredBy,
            "loopSettings": settings.dictionaryRepresentation,
            "store": dictProfiles
        ]
        
        return rval
    }
}

public struct TemporaryScheduleOverride {
    let targetRange: ClosedRange<Double>?
    let insulinNeedsScaleFactor: Double?
    let symbol: String?
    let duration: TimeInterval
    let name: String?

    public init(duration: TimeInterval, targetRange: ClosedRange<Double>?, insulinNeedsScaleFactor: Double?, symbol: String?, name: String?) {
        self.targetRange = targetRange
        self.insulinNeedsScaleFactor = insulinNeedsScaleFactor
        self.symbol = symbol
        self.duration = duration
        self.name = name
    }

    public var dictionaryRepresentation: [String: Any] {
        var rval: [String: Any] = [
            "duration": duration,
        ]

        if let symbol = symbol {
            rval["symbol"] = symbol
        }

        if let targetRange = targetRange {
            rval["targetRange"] = [targetRange.lowerBound, targetRange.upperBound]
        }

        if let insulinNeedsScaleFactor = insulinNeedsScaleFactor {
            rval["insulinNeedsScaleFactor"] = insulinNeedsScaleFactor
        }
        
        if let name = name {
            rval["name"] = name
        }
        
        return rval
    }
}

public struct LoopSettings {
    let dosingEnabled: Bool
    let overridePresets: [TemporaryScheduleOverride]
    let scheduleOverride: TemporaryScheduleOverride?
    let minimumBGGuard: Double?
    let preMealTargetRange: ClosedRange<Double>?
    let maximumBasalRatePerHour: Double?
    let maximumBolus: Double?
    let deviceToken: Data?
    let bundleIdentifier: String?

    public init(dosingEnabled: Bool, overridePresets: [TemporaryScheduleOverride], scheduleOverride: TemporaryScheduleOverride?, minimumBGGuard: Double?, preMealTargetRange: ClosedRange<Double>?, maximumBasalRatePerHour: Double?, maximumBolus: Double?,
                deviceToken: Data?, bundleIdentifier: String?) {
        self.dosingEnabled = dosingEnabled
        self.overridePresets = overridePresets
        self.scheduleOverride = scheduleOverride
        self.minimumBGGuard = minimumBGGuard
        self.preMealTargetRange = preMealTargetRange
        self.maximumBasalRatePerHour = maximumBasalRatePerHour
        self.maximumBolus = maximumBolus
        self.deviceToken = deviceToken
        self.bundleIdentifier = bundleIdentifier
    }

    public var dictionaryRepresentation: [String: Any] {

        var rval: [String: Any] = [
            "dosingEnabled": dosingEnabled,
            "overridePresets": overridePresets.map { $0.dictionaryRepresentation },
        ]

        if let minimumBGGuard = minimumBGGuard {
            rval["minimumBGGuard"] = minimumBGGuard
        }

        if let scheduleOverride = scheduleOverride {
            rval["scheduleOverride"] = scheduleOverride.dictionaryRepresentation
        }

        if let preMealTargetRange = preMealTargetRange {
            rval["preMealTargetRange"] = [preMealTargetRange.lowerBound, preMealTargetRange.upperBound]
        }

        if let maximumBasalRatePerHour = maximumBasalRatePerHour {
            rval["maximumBasalRatePerHour"] = maximumBasalRatePerHour
        }

        if let maximumBolus = maximumBolus {
            rval["maximumBolus"] = maximumBolus
        }
        
        if let deviceToken = deviceToken {
            rval["deviceToken"] = deviceToken.hexadecimalString
        }
        
        if let bundleIdentifier = bundleIdentifier {
            rval["bundleIdentifier"] = bundleIdentifier
        }

        return rval
    }
}
