import Foundation

struct FreeAPSSettings: JSON, Equatable {
    var units: GlucoseUnits = .mmolL
    var closedLoop: Bool = false
    var allowAnnouncements: Bool = false
    var useAutotune: Bool = false
    var isUploadEnabled: Bool = false
    var useLocalGlucoseSource: Bool = false
    var localGlucosePort: Int = 8080
    var debugOptions: Bool = false
    var insulinReqFraction: Decimal = 0.7
    var skipBolusScreenAfterCarbs: Bool = false
    var cgm: CGMType = .nightscout
    var uploadGlucose: Bool = false
    var useCalendar: Bool = false
}

extension FreeAPSSettings: Decodable {
    // Needed to decode incomplete JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var settings = FreeAPSSettings()

        if let units = try? container.decode(GlucoseUnits.self, forKey: .units) {
            settings.units = units
        }

        if let closedLoop = try? container.decode(Bool.self, forKey: .closedLoop) {
            settings.closedLoop = closedLoop
        }

        if let allowAnnouncements = try? container.decode(Bool.self, forKey: .allowAnnouncements) {
            settings.allowAnnouncements = allowAnnouncements
        }

        if let useAutotune = try? container.decode(Bool.self, forKey: .useAutotune) {
            settings.useAutotune = useAutotune
        }

        if let isUploadEnabled = try? container.decode(Bool.self, forKey: .isUploadEnabled) {
            settings.isUploadEnabled = isUploadEnabled
        }

        if let useLocalGlucoseSource = try? container.decode(Bool.self, forKey: .useLocalGlucoseSource) {
            settings.useLocalGlucoseSource = useLocalGlucoseSource
        }

        if let localGlucosePort = try? container.decode(Int.self, forKey: .localGlucosePort) {
            settings.localGlucosePort = localGlucosePort
        }

        if let debugOptions = try? container.decode(Bool.self, forKey: .debugOptions) {
            settings.debugOptions = debugOptions
        }

        if let insulinReqFraction = try? container.decode(Decimal.self, forKey: .insulinReqFraction) {
            settings.insulinReqFraction = insulinReqFraction
        }

        if let skipBolusScreenAfterCarbs = try? container.decode(Bool.self, forKey: .skipBolusScreenAfterCarbs) {
            settings.skipBolusScreenAfterCarbs = skipBolusScreenAfterCarbs
        }

        if let cgm = try? container.decode(CGMType.self, forKey: .cgm) {
            settings.cgm = cgm
        }

        if let uploadGlucose = try? container.decode(Bool.self, forKey: .uploadGlucose) {
            settings.uploadGlucose = uploadGlucose
        }

        if let useCalendar = try? container.decode(Bool.self, forKey: .useCalendar) {
            settings.useCalendar = useCalendar
        }

        self = settings
    }
}
