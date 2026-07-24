import CoreData
import Foundation

// a snapshot (DTO) of a CoreData OverridePresets entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct OverridePresetsSnapshot: Sendable {
    let id: String

    let name: String?
    let emoji: String?

    let percentage: Double

    let indefinite: Bool
    let duration: Decimal?

    let target: Decimal?

    let basal: Bool
    let cr: Bool
    let isf: Bool
    let isfAndCr: Bool

    let advancedSettings: Bool

    let endWIthNewCarbs: Bool
    let glucoseOverrideThreshold: Decimal?
    let glucoseOverrideThresholdActive: Bool
    let glucoseOverrideThresholdActiveDown: Bool
    let glucoseOverrideThresholdDown: Decimal?

    let overrideMaxIOB: Bool
    let maxIOB: Decimal?

    let smbIsAlwaysOff: Bool
    let smbIsOff: Bool
    let start: Decimal?
    let end: Decimal?

    let smbMinutes: Decimal?
    let uamMinutes: Decimal?

    let overrideAutoISF: Bool

    let date: Date?

    let aisf: AutoISFsettings?

    init(
        id: String,
        name: String? = nil,
        emoji: String? = nil,
        percentage: Double = 100,
        indefinite: Bool = false,
        duration: Decimal? = nil,
        target: Decimal? = nil,
        basal: Bool = false,
        cr: Bool = false,
        isf: Bool = false,
        isfAndCr: Bool = false,
        advancedSettings: Bool,
        endWIthNewCarbs: Bool = false,
        glucoseOverrideThreshold: Decimal? = nil,
        glucoseOverrideThresholdActive: Bool = false,
        glucoseOverrideThresholdActiveDown: Bool = false,
        glucoseOverrideThresholdDown: Decimal? = nil,
        overrideMaxIOB: Bool = false,
        maxIOB: Decimal? = nil,
        smbIsAlwaysOff: Bool = false,
        smbIsOff: Bool = false,
        start: Decimal? = nil,
        end: Decimal? = nil,
        smbMinutes: Decimal? = nil,
        uamMinutes: Decimal? = nil,
        overrideAutoISF: Bool = false,
        date: Date? = nil,
        aisf: AutoISFsettings? = nil
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
        self.aisf = aisf
    }
}

extension OverridePresetsSnapshot {
    static func create(from record: OverridePresets, aisf: AutoISFsettings?) -> OverridePresetsSnapshot? {
        guard let id = record.id else { return nil }
        return OverridePresetsSnapshot(
            id: id,
            name: record.name,
            emoji: record.emoji,
            percentage: record.percentage,
            indefinite: record.indefinite,
            duration: record.duration?.decimalValue,
            target: record.target?.decimalValue,
            basal: record.basal,
            cr: record.cr,
            isf: record.isf,
            isfAndCr: record.isfAndCr,
            advancedSettings: record.advancedSettings,
            endWIthNewCarbs: record.endWIthNewCarbs,
            glucoseOverrideThreshold: record.glucoseOverrideThreshold?.decimalValue,
            glucoseOverrideThresholdActive: record.glucoseOverrideThresholdActive,
            glucoseOverrideThresholdActiveDown: record.glucoseOverrideThresholdActiveDown,
            glucoseOverrideThresholdDown: record.glucoseOverrideThresholdDown?.decimalValue,
            overrideMaxIOB: record.overrideMaxIOB,
            maxIOB: record.maxIOB?.decimalValue,
            smbIsAlwaysOff: record.smbIsAlwaysOff,
            smbIsOff: record.smbIsOff,
            start: record.start?.decimalValue,
            end: record.end?.decimalValue,
            smbMinutes: record.smbMinutes?.decimalValue,
            uamMinutes: record.uamMinutes?.decimalValue,
            overrideAutoISF: record.overrideAutoISF,
            date: record.date,
            aisf: aisf
        )
    }
}
