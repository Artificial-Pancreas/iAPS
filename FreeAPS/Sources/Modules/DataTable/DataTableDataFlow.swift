import Foundation
import SwiftUI

enum DataTable {
    enum Config {}

    enum Mode: String, Hashable, Identifiable, CaseIterable {
        case treatments
        case glucose

        var id: String { rawValue }

        var name: String {
            var name: String = ""
            switch self {
            case .treatments:
                name = "Treatments"
            case .glucose:
                name = "Glucose"
            }
            return NSLocalizedString(name, comment: "History Mode")
        }
    }

    enum DataType: String, Equatable {
        case carbs
        case fpus
        case bolus
        case tempBasal
        case tempTarget
        case suspend
        case resume

        var name: String {
            var name: String = ""
            switch self {
            case .carbs:
                name = "Carbs"
            case .fpus:
                name = "Protein / Fat"
            case .bolus:
                name = "Bolus"
            case .tempBasal:
                name = "Temp Basal"
            case .tempTarget:
                name = "Temp Target"
            case .suspend:
                name = "Suspend"
            case .resume:
                name = "Resume"
            }

            return NSLocalizedString(name, comment: "Treatment type")
        }
    }

    class Treatment: Identifiable, Hashable, Equatable {
        let id: String
        let idPumpEvent: String?
        let units: GlucoseUnits
        let type: DataType
        let date: Date
        let amount: Decimal?
        let secondAmount: Decimal?
        let duration: Decimal?
        let isFPU: Bool?
        let fpuID: String?
        let note: String?
        let isSMB: Bool?
        let isExternal: Bool?

        private var numberFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var tempTargetFormater: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        init(
            units: GlucoseUnits,
            type: DataType,
            date: Date,
            amount: Decimal? = nil,
            secondAmount: Decimal? = nil,
            duration: Decimal? = nil,
            id: String? = nil,
            idPumpEvent: String? = nil,
            isFPU: Bool? = nil,
            fpuID: String? = nil,
            note: String? = nil,
            isSMB: Bool? = nil,
            isExternal: Bool? = nil
        ) {
            self.units = units
            self.type = type
            self.date = date
            self.amount = amount
            self.secondAmount = secondAmount
            self.duration = duration
            self.id = id ?? UUID().uuidString
            self.idPumpEvent = idPumpEvent
            self.isFPU = isFPU
            self.fpuID = fpuID
            self.note = note
            self.isSMB = isSMB
            self.isExternal = isExternal
        }

        static func == (lhs: Treatment, rhs: Treatment) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        var amountText: String {
            guard let amount = amount else {
                return ""
            }

            if amount == 0, duration == 0 {
                return "Cancel temp"
            }

            switch type {
            case .carbs:
                return numberFormatter
                    .string(from: amount as NSNumber)! + NSLocalizedString(" g", comment: "gram of carbs")
            case .fpus:
                return numberFormatter
                    .string(from: amount as NSNumber)! + NSLocalizedString(" g", comment: "gram of carb equilvalents")
            case .bolus:
                var bolusText = " "
                if isSMB ?? false {}
                else if isExternal ?? false {
                    bolusText += NSLocalizedString("External", comment: "External Insulin")
                } else {
                    bolusText += NSLocalizedString("Manual", comment: "Manual Bolus")
                }

                return numberFormatter
                    .string(from: amount as NSNumber)! + NSLocalizedString(" U", comment: "Insulin unit") + bolusText
            case .tempBasal:
                return numberFormatter
                    .string(from: amount as NSNumber)! + NSLocalizedString(" U/hr", comment: "Unit insulin per hour")
            case .tempTarget:
                var converted = amount
                if units == .mmolL {
                    converted = converted.asMmolL
                }

                guard var secondAmount = secondAmount else {
                    return numberFormatter.string(from: converted as NSNumber)! + " \(units.rawValue)"
                }
                if units == .mmolL {
                    secondAmount = secondAmount.asMmolL
                }

                return tempTargetFormater.string(from: converted as NSNumber)! + " - " + tempTargetFormater
                    .string(from: secondAmount as NSNumber)! + " \(units.rawValue)"
            case .resume,
                 .suspend:
                return type.name
            }
        }

        var color: Color {
            switch type {
            case .carbs:
                return .loopYellow
            case .fpus:
                return .orange.opacity(0.5)
            case .bolus:
                return Color.insulin
            case .tempBasal:
                return Color.insulin.opacity(0.4)
            case .resume,
                 .suspend,
                 .tempTarget:
                return .loopGray
            }
        }

        var durationText: String? {
            guard let duration = duration, duration > 0 else {
                return nil
            }
            return numberFormatter.string(from: duration as NSNumber)! + " min"
        }
    }

    class Glucose: Identifiable, Hashable, Equatable {
        static func == (lhs: DataTable.Glucose, rhs: DataTable.Glucose) -> Bool {
            lhs.glucose == rhs.glucose
        }

        let glucose: BloodGlucose

        init(glucose: BloodGlucose) {
            self.glucose = glucose
        }

        var id: String { glucose.id }
    }
}

protocol DataTableProvider: Provider {
    func pumpHistory() -> [PumpHistoryEvent]
    func tempTargets() -> [TempTarget]
    func carbs() -> [CarbsEntry]
    func glucose() -> [BloodGlucose]
    func deleteCarbs(_ treatement: DataTable.Treatment)
    func deleteInsulin(_ treatement: DataTable.Treatment)
    func deleteGlucose(id: String)
}
