
import Foundation
import SwiftUI

struct ShapeModel: Identifiable {
    var type: String
    var percent: Decimal
    var id = UUID()
}

struct ChartData: Identifiable {
    var date: Date
    var iob: Double
    var zt: Double
    var cob: Double
    var uam: Double
    var id = UUID()
}

struct InsulinRequired: Identifiable {
    let agent: String
    var amount: Decimal
    let id = UUID()
}

struct Thresholds: Identifiable, Equatable {
    var id: String { UUID().uuidString }
    let glucose: String
    let setting: String
    let threshold: String
}

struct Table: Identifiable, Equatable {
    var id: String { UUID().uuidString }
    var point: String { "•" }
    let localizedString: LocalizedStringKey
}

struct BolusSummary: Identifiable, Equatable {
    var id: String { UUID().uuidString }
    let variable: String
    let formula: String
    let insulin: Decimal
    let color: Color
}

struct Formulas: Identifiable, Equatable {
    var id: String { UUID().uuidString }
    let variable: String
    let value: String
    let unit: String
    let color: Color
}

struct GlucoseData: Identifiable {
    let glucose: Double
    var type: String
    var time: Date
    let id = UUID()
}

struct IOBData: Identifiable {
    var date: Date
    var iob: Decimal
    var cob: Decimal
    var id = UUID()
}

struct tddData {
    var date: Date
    var tdd: Decimal
}
