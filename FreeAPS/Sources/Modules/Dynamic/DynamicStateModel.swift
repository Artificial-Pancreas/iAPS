import SwiftUI

extension Dynamic {
    final class StateModel: BaseStateModel<Provider> {
        private let coreDataStorage = CoreDataStorage()

        @Published var useNewFormula: Bool = false
        @Published var enableDynamicCR: Bool = false
        @Published var sigmoid: Bool = false
        @Published var adjustmentFactor: Decimal = 0.5
        @Published var weightPercentage: Decimal = 0.65
        @Published var unit: GlucoseUnits = .mmolL
        @Published var averages: (isf: Double, cr: Double, days: Double)?
        @Published var aisf = false

        override func subscribe() async {
            let settings = await settingsManager.settings
            let preferences = await settingsManager.preferences

            unit = settings.units
            useNewFormula = preferences.useNewFormula
            enableDynamicCR = preferences.enableDynamicCR
            sigmoid = preferences.sigmoid
            adjustmentFactor = preferences.adjustmentFactor
            weightPercentage = preferences.weightPercentage
            averages = await thirtyDaysAverages()
            aisf = settings.autoisf
        }

        func saveIfChanged() {
            Task {
                let preferences = await settingsManager.preferences
                let unChanged = preferences.enableDynamicCR == enableDynamicCR &&
                    preferences.adjustmentFactor == adjustmentFactor &&
                    preferences.sigmoid == sigmoid &&
                    preferences.useNewFormula == useNewFormula &&
                    preferences.weightPercentage == weightPercentage

                guard !unChanged else { return }
                var newSettings = preferences
                newSettings.enableDynamicCR = enableDynamicCR
                newSettings.adjustmentFactor = adjustmentFactor
                newSettings.sigmoid = sigmoid
                newSettings.useNewFormula = useNewFormula
                newSettings.weightPercentage = weightPercentage
                newSettings.timestamp = Date()
                await settingsManager.updatePreferences(newSettings)
            }
        }

        private func thirtyDaysAverages() async -> (isf: Double, cr: Double, days: Double)? {
            let reasons = await coreDataStorage.fetchReasons(interval: DateFilter.month.startDate)
            let currentUnitIsMmol = unit == .mmolL
            let history = reasons.filter({ $0.mmol == currentUnitIsMmol }).sorted(by: { $0.date ?? Date() > $1.date ?? Date() })
            let days = -1 * (history.last?.date ?? .now).timeIntervalSince(history.first?.date ?? .now) / 8.64E4
            // Avoid displaying "0 days"
            let isf = history.compactMap(\.isf)
            let cr = history.compactMap(\.cr)
            guard !isf.isEmpty, !cr.isEmpty, days >= 0.06 else { return nil }

            let totalISF = isf.reduce(0, { x, y in
                x + (y as Decimal)
            })
            let totalCR = cr.reduce(0, { x, y in
                x + (y as Decimal)
            })
            let averageCR = Double(totalCR) / Double(cr.count)
            let averageISF = Double(totalISF) / Double(isf.count)

            return (averageISF, averageCR, days)
        }
    }
}
