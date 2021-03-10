import Foundation

struct FreeAPSSettings: JSON {
    var units: GlucoseUnits
    var closedLoop: Bool
    var allowAnnouncements: Bool
}
