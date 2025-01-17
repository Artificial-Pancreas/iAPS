import Foundation

struct DynamicVariables: JSON, Codable {
    var average_total_data: Decimal
    var weightedAverage: Decimal
    var weigthPercentage: Decimal
    var past2hoursAverage: Decimal
    var date: Date
    var isEnabled: Bool
    var presetActive: Bool
    var overridePercentage: Decimal
    var useOverride: Bool
    var duration: Decimal
    var unlimited: Bool
    var hbt: Decimal
    var overrideTarget: Decimal
    var smbIsOff: Bool
    var advancedSettings: Bool
    var isfAndCr: Bool
    var isf: Bool
    var cr: Bool
    var smbIsAlwaysOff: Bool
    var start: Decimal
    var end: Decimal
    var smbMinutes: Decimal
    var uamMinutes: Decimal
    var maxIOB: Decimal
    var overrideMaxIOB: Bool
    var disableCGMError: Bool
    var preset: String
    var autoISFoverrides: AutoISFsettings
    var aisfOverridden: Bool

    init(
        average_total_data: Decimal,
        weightedAverage: Decimal,
        weigthPercentage: Decimal,
        past2hoursAverage: Decimal,
        date: Date,
        isEnabled: Bool,
        presetActive: Bool,
        overridePercentage: Decimal,
        useOverride: Bool,
        duration: Decimal,
        unlimited: Bool,
        hbt: Decimal,
        overrideTarget: Decimal,
        smbIsOff: Bool,
        advancedSettings: Bool,
        isfAndCr: Bool,
        isf: Bool,
        cr: Bool,
        smbIsAlwaysOff: Bool,
        start: Decimal,
        end: Decimal,
        smbMinutes: Decimal,
        uamMinutes: Decimal,
        maxIOB: Decimal,
        overrideMaxIOB: Bool,
        disableCGMError: Bool,
        preset: String,
        autoISFoverrides: AutoISFsettings,
        aisfOverridden: Bool
    ) {
        self.average_total_data = average_total_data
        self.weightedAverage = weightedAverage
        self.weigthPercentage = weigthPercentage
        self.past2hoursAverage = past2hoursAverage
        self.date = date
        self.isEnabled = isEnabled
        self.presetActive = presetActive
        self.overridePercentage = overridePercentage
        self.useOverride = useOverride
        self.duration = duration
        self.unlimited = unlimited
        self.hbt = hbt
        self.overrideTarget = overrideTarget
        self.smbIsOff = smbIsOff
        self.advancedSettings = advancedSettings
        self.isfAndCr = isfAndCr
        self.isf = isf
        self.cr = cr
        self.smbIsAlwaysOff = smbIsAlwaysOff
        self.start = start
        self.end = end
        self.smbMinutes = smbMinutes
        self.uamMinutes = uamMinutes
        self.maxIOB = maxIOB
        self.overrideMaxIOB = overrideMaxIOB
        self.disableCGMError = disableCGMError
        self.preset = preset
        self.autoISFoverrides = autoISFoverrides
        self.aisfOverridden = aisfOverridden
    }
}

extension DynamicVariables {
    private enum CodingKeys: String, CodingKey {
        case average_total_data
        case weightedAverage
        case weigthPercentage
        case past2hoursAverage
        case date
        case isEnabled
        case presetActive
        case overridePercentage
        case useOverride
        case duration
        case unlimited
        case hbt
        case overrideTarget
        case smbIsOff
        case advancedSettings
        case isfAndCr
        case isf
        case cr
        case smbIsAlwaysOff
        case start
        case end
        case smbMinutes
        case uamMinutes
        case maxIOB
        case overrideMaxIOB
        case disableCGMError
        case preset
        case autoISFoverrides
        case aisfOverridden
    }
}

// TDD
struct Basal {
    var amount: Decimal
    var noneComputed: Date?
    var nonComputedAmount: Decimal
    var time: Date?
    var duration: Double?
}

struct SkippedBasals {
    var amount: Decimal
    var time: Date?
    var duration: Double?
}

struct Reduce {
    var amount: Decimal?
}
