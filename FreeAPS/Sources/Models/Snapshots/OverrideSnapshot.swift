import CoreData
import Foundation

// a snapshot (DTO) of a CoreData Override entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct OverrideSnapshot: Sendable, Equatable {
    let advancedSettings: Bool
    let basal: Bool
    let cr: Bool
    let date: Date?
    let duration: Decimal?
    let enabled: Bool
    let end: Decimal?
    let endWIthNewCarbs: Bool
    let glucoseOverrideThreshold: Decimal?
    let glucoseOverrideThresholdActive: Bool
    let glucoseOverrideThresholdActiveDown: Bool
    let glucoseOverrideThresholdDown: Decimal?
    let id: String?
    let indefinite: Bool
    let isf: Bool
    let isfAndCr: Bool
    let isPreset: Bool
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
}

extension OverrideSnapshot {
    static func create(from override: Override) -> OverrideSnapshot {
        OverrideSnapshot(
            advancedSettings: override.advancedSettings,
            basal: override.basal,
            cr: override.cr,
            date: override.date,
            duration: override.duration?.decimalValue,
            enabled: override.enabled,
            end: override.end?.decimalValue,
            endWIthNewCarbs: override.endWIthNewCarbs,
            glucoseOverrideThreshold: override.glucoseOverrideThreshold?.decimalValue,
            glucoseOverrideThresholdActive: override.glucoseOverrideThresholdActive,
            glucoseOverrideThresholdActiveDown: override.glucoseOverrideThresholdActiveDown,
            glucoseOverrideThresholdDown: override.glucoseOverrideThresholdDown?.decimalValue,
            id: override.id,
            indefinite: override.indefinite,
            isf: override.isf,
            isfAndCr: override.isfAndCr,
            isPreset: override.isPreset,
            maxIOB: override.maxIOB?.decimalValue,
            overrideAutoISF: override.overrideAutoISF,
            overrideMaxIOB: override.overrideMaxIOB,
            percentage: override.percentage,
            smbIsAlwaysOff: override.smbIsAlwaysOff,
            smbIsOff: override.smbIsOff,
            smbMinutes: override.smbMinutes?.decimalValue,
            start: override.start?.decimalValue,
            target: override.target?.decimalValue,
            uamMinutes: override.uamMinutes?.decimalValue
        )
    }
}
