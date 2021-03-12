import Foundation

public struct PredictionLineData: Identifiable, Hashable {

    public var id = UUID()
    let type: PredictionType
    let values: [BloodGlucose]

    func count() -> Int { values.count }
}
