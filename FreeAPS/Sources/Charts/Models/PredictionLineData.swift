import Foundation

public struct PredictionLineData: Identifiable, Hashable {
    public var id = UUID()
    let type: PredictionType
    var values: [BloodGlucose]
}
