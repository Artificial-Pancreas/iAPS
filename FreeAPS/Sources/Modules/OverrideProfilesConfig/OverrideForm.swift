import Foundation

extension OverrideProfilesConfig {
    struct OverrideForm: Sendable {
        var percentage: Double = 100
        var _indefinite: Bool = true
        var duration: Decimal = 0
        var target: Decimal = 0 // display units
        var override_target: Bool = false
        var smbIsOff: Bool = false
        var advancedSettings: Bool = false
        var isfAndCr: Bool = true
        var isf: Bool = true
        var cr: Bool = true
        var basal: Bool = true
        var smbIsAlwaysOff: Bool = false
        var start: Decimal = 0
        var end: Decimal = 23
        var smbMinutes: Decimal = 0
        var uamMinutes: Decimal = 0
        var maxIOB: Decimal = 0
        var overrideMaxIOB: Bool = false
        var endWIthNewCarbs: Bool = false
        var overrideAutoISF: Bool = false
        var glucoseOverrideThresholdActive: Bool = false
        var glucoseOverrideThreshold: Decimal = 100 // mgdL
        var glucoseOverrideThresholdActiveDown: Bool = false
        var glucoseOverrideThresholdDown: Decimal = 90 // mgdL
        var autoISFsettings = AutoISFsettings()
    }
}

extension OverrideProfilesConfig.OverrideForm {
    /// Read-only configuration the form needs but never edits.
    struct Context: Sendable {
        var units: GlucoseUnits
        var extendedOverrides: Bool
        var defaultSmbMinutes: Decimal
        var defaultUamMinutes: Decimal
        var defaultMaxIOB: Decimal
        var currentAutoIsfSettings: AutoISFsettings
    }

    /// A fresh form with app/preference defaults applied (mirrors the old `resetToDefaults`).
    static func defaults(context: Context) -> Self {
        var form = Self()
        form.target = context.units == .mmolL ? 5 : 100
        form.smbMinutes = context.defaultSmbMinutes
        form.uamMinutes = context.defaultUamMinutes
        form.maxIOB = context.defaultMaxIOB
        form.autoISFsettings = context.currentAutoIsfSettings
        return form
    }

    init(from preset: OverridePresetsSnapshot, context: Context) {
        self = Self.defaults(context: context)

        percentage = preset.percentage
        _indefinite = preset.indefinite
        duration = preset.duration ?? 0
        smbIsOff = preset.smbIsOff
        advancedSettings = preset.advancedSettings
        isfAndCr = preset.isfAndCr
        isf = preset.isf
        cr = preset.cr
        basal = preset.basal
        smbIsAlwaysOff = preset.smbIsAlwaysOff
        overrideMaxIOB = preset.overrideMaxIOB
        overrideAutoISF = preset.overrideAutoISF
        endWIthNewCarbs = preset.endWIthNewCarbs
        glucoseOverrideThresholdActive = preset.glucoseOverrideThresholdActive
        glucoseOverrideThresholdActiveDown = preset.glucoseOverrideThresholdActiveDown

        if glucoseOverrideThresholdActive {
            glucoseOverrideThreshold = preset.glucoseOverrideThreshold ?? 100
        }
        if glucoseOverrideThresholdActiveDown {
            glucoseOverrideThresholdDown = preset.glucoseOverrideThresholdDown ?? 100
        }
        if smbIsAlwaysOff {
            start = preset.start ?? 0
            end = preset.end ?? 0
        }

        smbMinutes = preset.smbMinutes ?? context.defaultSmbMinutes
        uamMinutes = preset.uamMinutes ?? context.defaultUamMinutes
        maxIOB = preset.maxIOB ?? context.defaultMaxIOB

        autoISFsettings = preset.aisf ?? context.currentAutoIsfSettings

        override_target = Double(preset.target ?? 0) > 6.0
        let mgdlTarget = preset.target ?? 0
        target = context.units == .mmolL ? mgdlTarget.asMmolL : mgdlTarget
    }

    func snapshot(id: String, name: String?, emoji: String?, context: Context) -> OverridePresetsSnapshot {
        OverridePresetsSnapshot(
            id: id,
            name: name,
            emoji: emoji,
            percentage: percentage.rounded(),
            indefinite: _indefinite,
            duration: duration,
            target: override_target ? (context.units == .mmolL ? target.asMgdL : target) : 6,
            basal: basal,
            cr: cr,
            isf: isf,
            isfAndCr: isfAndCr,
            advancedSettings: advancedSettings,
            endWIthNewCarbs: endWIthNewCarbs,
            glucoseOverrideThreshold: glucoseOverrideThreshold,
            glucoseOverrideThresholdActive: glucoseOverrideThresholdActive,
            glucoseOverrideThresholdActiveDown: glucoseOverrideThresholdActiveDown,
            glucoseOverrideThresholdDown: glucoseOverrideThresholdDown,
            overrideMaxIOB: overrideMaxIOB,
            maxIOB: maxIOB,
            smbIsAlwaysOff: smbIsAlwaysOff,
            smbIsOff: smbIsOff,
            start: start,
            end: end,
            smbMinutes: smbMinutes,
            uamMinutes: uamMinutes,
            overrideAutoISF: overrideAutoISF,
            aisf: autoISFsettings
        )
    }
}
