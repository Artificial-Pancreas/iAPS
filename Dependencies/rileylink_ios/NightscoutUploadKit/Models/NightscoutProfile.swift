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

fileprivate let reverseTimeZoneMap = timeZoneMap.reduce(into: [String: String]()) { (dict, entry) in
    dict[entry.value] = entry.key
}

public class ProfileSet {
    typealias RawValue = [String: Any]

    public typealias ProfileStore = [String: Profile]
    typealias ProfileStoreRawValue = [String: Profile.RawValue]
    
    public struct ScheduleItem {
        typealias RawValue = [String: Any]

        public let offset: TimeInterval
        public let value: Double
        
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

        init?(rawValue: RawValue) {
            guard
                let timeAsSeconds = rawValue["timeAsSeconds"] as? Double,
                let value = rawValue["value"] as? Double
            else {
                return nil
            }

            self.offset = TimeInterval(timeAsSeconds)
            self.value = value
        }
    }
    
    public struct Profile {
        typealias RawValue = [String: Any]

        public let timeZone: TimeZone
        public let dia: TimeInterval
        public let sensitivity: [ScheduleItem]
        public let carbratio: [ScheduleItem]
        public let basal: [ScheduleItem]
        public let targetLow: [ScheduleItem]
        public let targetHigh: [ScheduleItem]
        public let units: String?

        public init(timezone: TimeZone, dia: TimeInterval, sensitivity: [ScheduleItem], carbratio: [ScheduleItem], basal: [ScheduleItem], targetLow: [ScheduleItem], targetHigh: [ScheduleItem], units: String) {
            self.timeZone = timezone
            self.dia = dia
            self.sensitivity = sensitivity
            self.carbratio = carbratio
            self.basal = basal
            self.targetLow = targetLow
            self.targetHigh = targetHigh
            self.units = units
        }

        public var dictionaryRepresentation: [String: Any] {
            var rval: [String: Any] = [
                "dia": dia.hours,
                "carbs_hr": "0",
                "delay": "0",
                "timezone": timeZoneMap[timeZone.identifier] ?? timeZone.identifier,
                "target_low": targetLow.map { $0.dictionaryRepresentation },
                "target_high": targetHigh.map { $0.dictionaryRepresentation },
                "sens": sensitivity.map { $0.dictionaryRepresentation },
                "basal": basal.map { $0.dictionaryRepresentation },
                "carbratio": carbratio.map { $0.dictionaryRepresentation },
                ]
            rval["units"] = units
            return rval
        }

        init?(rawValue: RawValue) {
            guard
                let nsTimezoneIdentifier = rawValue["timezone"] as? String,
                let timeZoneIdentifier = reverseTimeZoneMap[nsTimezoneIdentifier],
                let timeZone = TimeZone(identifier: timeZoneIdentifier),
                let diaHours = rawValue["dia"] as? Double,
                let sensitivityRaw = rawValue["sens"] as? [ScheduleItem.RawValue],
                let carbratioRaw = rawValue["carbratio"] as? [ScheduleItem.RawValue],
                let basalRaw = rawValue["basal"] as? [ScheduleItem.RawValue],
                let targetLowRaw = rawValue["target_low"] as? [ScheduleItem.RawValue],
                let targetHighRaw = rawValue["target_high"] as? [ScheduleItem.RawValue]
            else {
                return nil
            }

            self.timeZone = timeZone
            self.dia = TimeInterval(hours: diaHours)
            self.sensitivity = sensitivityRaw.compactMap { ScheduleItem(rawValue: $0) }
            self.carbratio = carbratioRaw.compactMap { ScheduleItem(rawValue: $0) }
            self.basal = basalRaw.compactMap { ScheduleItem(rawValue: $0) }
            self.targetLow = targetLowRaw.compactMap { ScheduleItem(rawValue: $0) }
            self.targetHigh = targetHighRaw.compactMap { ScheduleItem(rawValue: $0) }
            self.units = rawValue["units"] as? String
         }
    }
    
    public let startDate : Date
    public let units: String
    public let enteredBy: String
    public let defaultProfile: String
    public let store: ProfileStore
    public let settings: LoopSettings
    
    public init(startDate: Date, units: String, enteredBy: String, defaultProfile: String, store: ProfileStore, settings: LoopSettings) {
        self.startDate = startDate
        self.units = units
        self.enteredBy = enteredBy
        self.defaultProfile = defaultProfile
        self.store = store
        self.settings = settings
    }
    
    public var dictionaryRepresentation: [String: Any] {
        let dateFormatter = ISO8601DateFormatter.defaultFormatter()
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

    init?(rawValue: RawValue) {
        guard
            let startDateStr = rawValue["startDate"] as? String,
            let startDate = TimeFormat.dateFromTimestamp(startDateStr),
            let units = rawValue["units"] as? String,
            let enteredBy = rawValue["enteredBy"] as? String,
            let defaultProfile = rawValue["defaultProfile"] as? String,
            let storeRaw = rawValue["store"] as? ProfileStoreRawValue,
            let settingsRaw = rawValue["loopSettings"] as? LoopSettings.RawValue,
            let settings = LoopSettings(rawValue: settingsRaw)
        else {
            return nil
        }

        self.startDate = startDate
        self.units = units
        self.enteredBy = enteredBy
        self.defaultProfile = defaultProfile
        self.store = storeRaw.compactMapValues { Profile(rawValue: $0) }
        self.settings = settings
    }
}
