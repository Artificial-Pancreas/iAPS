import Foundation

public struct InformationBarEntryData: Identifiable, Hashable {
    public init(id: UUID = UUID(), label: String, type: APSDataTypes, value: Double) {
        self.id = id
        self.label = label
        self.value = value
        self.type = type
    }

    public var id = UUID()
    let label: String
    let value: Double
    let type: APSDataTypes
}
