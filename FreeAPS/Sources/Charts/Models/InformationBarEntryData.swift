import Foundation

public struct InformationBarEntryData: Identifiable, Hashable {
    public var id = UUID()
    let label: String
    let value: Double
    let type: APSDataTypes
}
