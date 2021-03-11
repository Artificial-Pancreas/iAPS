import Foundation

public struct PredictionLineData: Identifiable, Hashable {
    public init(id: UUID = UUID(), type: PredictionType, values: [Double]) {
        self.id = id
        self.type = type
        self.values = values
    }

    public var id = UUID()
    let type: PredictionType
    let values: [Double]

    func max() -> Int { values.count }
}
