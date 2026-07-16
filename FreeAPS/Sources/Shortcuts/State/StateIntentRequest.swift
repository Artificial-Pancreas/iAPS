import AppIntents
import Foundation

enum StateIntentError: Error {
    case StateIntentUnknownError
    case NoBG
    case NoIOBCOB
}

struct StateiAPSResults: AppEntity {
    static let defaultQuery = StateBGQuery()

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "iAPS State Result"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(glucose)")
    }

    var id: UUID
    @Property(title: "Glucose") var glucose: String

    @Property(title: "Trend") var trend: String

    @Property(title: "Delta") var delta: String

    @Property(title: "Date") var date: Date

    @Property(title: "IOB") var iob: Double?

    @Property(title: "COB") var cob: Double?

    @Property(title: "unit") var unit: String?

    init(glucose: String, trend: String, delta: String, date: Date, iob: Double, cob: Double, unit: GlucoseUnits) {
        id = UUID()
        self.glucose = glucose
        self.trend = trend
        self.delta = delta
        self.date = date
        self.iob = iob
        self.cob = cob
        self.unit = unit.rawValue
    }
}

struct StateBGQuery: EntityQuery {
    @MainActor func entities(for _: [StateiAPSResults.ID]) async throws -> [StateiAPSResults] {
        []
    }

    @MainActor func suggestedEntities() async throws -> [StateiAPSResults] {
        []
    }
}

final class StateIntentRequest: BaseIntentsRequest {
    func getLastBG() async throws -> (dateGlucose: Date, glucose: String, trend: String, delta: String) {
        let glucose = await glucoseStorage.retrieve()
        guard let lastGlucose = glucose.last, let glucoseValue = lastGlucose.glucose else { throw StateIntentError.NoBG }
        let delta = glucose.count >= 2 ? glucoseValue - (glucose[glucose.count - 2].glucose ?? 0) : nil

        let settings = await settingsManager.settings
        let units = settings.units

        let glucoseFormatter = self.glucoseFormatter(settings)

        let glucoseText = glucoseFormatter
            .string(from: Double(
                units == .mmolL ? glucoseValue
                    .asMmolL : Decimal(glucoseValue)
            ) as NSNumber)!
        let directionText = lastGlucose.direction?.rawValue ?? "none"
        let deltaText = delta
            .map {
                Self.deltaFormatter
                    .string(from: Double(
                        units == .mmolL ? $0
                            .asMmolL : Decimal($0)
                    ) as NSNumber)!
            } ?? "--"

        return (lastGlucose.dateString, glucoseText, directionText, deltaText)
    }

    func getIOB_COB() async throws -> (iob: Double, cob: Double) {
        let suggestion = appCoordinator.suggested.value
        let iob = suggestion?.iob ?? 0.0
        let cob = suggestion?.cob ?? 0.0
        let iob_double = Double(truncating: iob as NSNumber)
        let cob_double = Double(truncating: cob as NSNumber)
        return (iob_double, cob_double)
    }

    private func glucoseFormatter(_ settings: FreeAPSSettings) -> NumberFormatter {
        switch settings.units {
        case .mmolL: return Self.glucoseFormatterMmol
        case .mgdL: return Self.glucoseFormatterMgdl
        }
    }

    private static let glucoseFormatterMmol = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let glucoseFormatterMgdl = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let deltaFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter
    }()
}
