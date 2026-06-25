import Foundation

struct PumpHistoryEvent: JSON, Equatable {
    let id: String
    let type: EventType
    let timestamp: Date
    let isMutable: Bool?
    let amount: Decimal?
    let duration: Decimal? // used for bolus duratin, in minutes, rounded to 1 decimal
    let durationMin: Decimal? // rounded to 1 decimal
    let rate: Decimal?
    let deliveredUnits: Decimal?
    let temp: TempType?
    let carbInput: Int?
    let note: String?
    let isSMB: Bool?
    let isExternal: Bool?

    init(
        id: String,
        type: EventType,
        timestamp: Date,
        isMutable: Bool? = nil,
        amount: Decimal? = nil,
        duration: Decimal? = nil,
        durationMin: Decimal? = nil,
        rate: Decimal? = nil,
        deliveredUnits: Decimal? = nil, // delivered units for a finalized TBR
        temp: TempType? = nil,
        carbInput: Int? = nil,
        note: String? = nil,
        isSMB: Bool? = nil,
        isExternal: Bool? = nil
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.amount = amount
        self.duration = duration
        self.durationMin = durationMin
        self.rate = rate
        self.deliveredUnits = deliveredUnits
        self.temp = temp
        self.carbInput = carbInput
        self.note = note
        self.isSMB = isSMB
        self.isExternal = isExternal
        self.isMutable = isMutable
    }
}

enum EventType: String, JSON {
    case bolus = "Bolus"
    case smb = "SMB"
    case isExternal = "External Insulin"
    case mealBolus = "Meal Bolus"
    case correctionBolus = "Correction Bolus"
    case snackBolus = "Snack Bolus"
    case bolusWizard = "BolusWizard"
    case tempBasal = "TempBasal"
    case tempBasalDuration = "TempBasalDuration"
    case pumpSuspend = "PumpSuspend"
    case pumpResume = "PumpResume"
    case pumpAlarm = "PumpAlarm"
    case pumpBattery = "PumpBattery"
    case rewind = "Rewind"
    case prime = "Prime"
    case journalCarbs = "JournalEntryMealMarker"

    case nsTempBasal = "Temp Basal"
    case nsCarbCorrection = "Carb Correction"
    case nsTempTarget = "Temporary Target"
    case nsInsulinChange = "Insulin Change"
    case nsSiteChange = "Site Change"
    case nsBatteryChange = "Pump Battery Change"
    case nsAnnouncement = "Announcement"
    case nsSensorChange = "Sensor Start"
    case capillaryGlucose = "BG Check"
    case nsExercise = "Exercise"
}

enum TempType: String, JSON {
    case absolute
    case percent
}

extension PumpHistoryEvent {
    private enum CodingKeys: String, CodingKey {
        case id
        case type = "_type"
        case timestamp
        case isMutable
        case amount
        case duration
        case durationMin = "duration (min)"
        case rate
        case deliveredUnits
        case temp
        case carbInput = "carb_input"
        case note
        case isSMB
        case isExternal
    }
}

struct PumpHistoryEventIdentity: Equatable, Hashable {
    let type: EventType
    let timestamp: Date
}

extension PumpHistoryEvent {
    // this is used by the pump history storage to update the existing entries
    var identity: PumpHistoryEventIdentity {
        PumpHistoryEventIdentity(
            type: type,
            timestamp: timestamp.truncatedToSecond
        )
    }
}
