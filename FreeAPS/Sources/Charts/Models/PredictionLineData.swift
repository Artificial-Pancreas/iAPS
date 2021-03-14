import Foundation

struct PredictionLineData: Identifiable, Hashable {
    var id = UUID()
    let type: PredictionType
    var values: [BloodGlucose]
}
