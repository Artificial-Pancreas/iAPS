import CoreData
import Foundation

// a snapshot (DTO) of a CoreData OverridePresets entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct OverridePresetsSnapshot: Sendable {
    let id: String?
    var date: Date?
    let end: Decimal?
    let name: String?
    let emoji: String?
    let advancedSettings: Bool
    let basal: Bool
    let cr: Bool
    let duration: Decimal?
    let endWIthNewCarbs: Bool
    let glucoseOverrideThreshold: Decimal?
    let glucoseOverrideThresholdActive: Bool
    let glucoseOverrideThresholdActiveDown: Bool
    let glucoseOverrideThresholdDown: Decimal?
    let indefinite: Bool
    let isf: Bool
    let isfAndCr: Bool
    let maxIOB: Decimal?
    let overrideAutoISF: Bool
    let overrideMaxIOB: Bool
    let percentage: Double
    let smbIsAlwaysOff: Bool
    let smbIsOff: Bool
    let smbMinutes: Decimal?
    let start: Decimal?
    let target: Decimal?
    let uamMinutes: Decimal?

    init(
        id: String? = nil,
        date: Date? = nil,
        end: Decimal? = nil,
        name: String? = nil,
        emoji: String? = nil,
        advancedSettings: Bool,
        basal: Bool = false,
        cr: Bool = false,
        duration: Decimal? = nil,
        endWIthNewCarbs: Bool = false,
        glucoseOverrideThreshold: Decimal? = nil,
        glucoseOverrideThresholdActive: Bool = false,
        glucoseOverrideThresholdActiveDown: Bool = false,
        glucoseOverrideThresholdDown: Decimal? = nil,
        indefinite: Bool = false,
        isf: Bool = false,
        isfAndCr: Bool = false,
        maxIOB: Decimal? = nil,
        overrideAutoISF: Bool = false,
        overrideMaxIOB: Bool = false,
        percentage: Double = 100,
        smbIsAlwaysOff: Bool = false,
        smbIsOff: Bool = false,
        smbMinutes: Decimal? = nil,
        start: Decimal? = nil,
        target: Decimal? = nil,
        uamMinutes: Decimal? = nil,
    ) {
        self.advancedSettings = advancedSettings
        self.basal = basal
        self.cr = cr
        self.date = date
        self.duration = duration
        self.emoji = emoji
        self.end = end
        self.endWIthNewCarbs = endWIthNewCarbs
        self.glucoseOverrideThreshold = glucoseOverrideThreshold
        self.glucoseOverrideThresholdActive = glucoseOverrideThresholdActive
        self.glucoseOverrideThresholdActiveDown = glucoseOverrideThresholdActiveDown
        self.glucoseOverrideThresholdDown = glucoseOverrideThresholdDown
        self.id = id
        self.indefinite = indefinite
        self.isf = isf
        self.isfAndCr = isfAndCr
        self.maxIOB = maxIOB
        self.name = name
        self.overrideAutoISF = overrideAutoISF
        self.overrideMaxIOB = overrideMaxIOB
        self.percentage = percentage
        self.smbIsAlwaysOff = smbIsAlwaysOff
        self.smbIsOff = smbIsOff
        self.smbMinutes = smbMinutes
        self.start = start
        self.target = target
        self.uamMinutes = uamMinutes
    }
}

extension OverridePresetsSnapshot {
    static func create(from record: OverridePresets) -> OverridePresetsSnapshot {
        OverridePresetsSnapshot(
            id: record.id,
            date: record.date,
            end: record.end?.decimalValue,
            name: record.name,
            emoji: record.emoji,
            advancedSettings: record.advancedSettings,
            basal: record.basal,
            cr: record.cr,
            duration: record.duration?.decimalValue,
            endWIthNewCarbs: record.endWIthNewCarbs,
            glucoseOverrideThreshold: record.glucoseOverrideThreshold?.decimalValue,
            glucoseOverrideThresholdActive: record.glucoseOverrideThresholdActive,
            glucoseOverrideThresholdActiveDown: record.glucoseOverrideThresholdActiveDown,
            glucoseOverrideThresholdDown: record.glucoseOverrideThresholdDown?.decimalValue,
            indefinite: record.indefinite,
            isf: record.isf,
            isfAndCr: record.isfAndCr,
            maxIOB: record.maxIOB?.decimalValue,
            overrideAutoISF: record.overrideAutoISF,
            overrideMaxIOB: record.overrideMaxIOB,
            percentage: record.percentage,
            smbIsAlwaysOff: record.smbIsAlwaysOff,
            smbIsOff: record.smbIsOff,
            smbMinutes: record.smbMinutes?.decimalValue,
            start: record.start?.decimalValue,
            target: record.target?.decimalValue,
            uamMinutes: record.uamMinutes?.decimalValue
        )
    }
}
