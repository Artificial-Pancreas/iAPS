import SwiftUI

extension Dynamic {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!

        @Published var useNewFormula: Bool = false
        @Published var enableDynamicCR: Bool = false
        @Published var sigmoid: Bool = false
        @Published var adjustmentFactor: Decimal = 0.5
        @Published var weightPercentage: Decimal = 0.65
        @Published var threshold_setting: Decimal = 65
        @Published var unit: GlucoseUnits = .mmolL
        @Published var averages: (isf: Double, cr: Double, days: Double)?
        @Published var aisf = false

        var preferences: Preferences {
            settingsManager.preferences
        }

        override func subscribe() {
            unit = settingsManager.settings.units
            useNewFormula = settings.preferences.useNewFormula
            enableDynamicCR = settings.preferences.enableDynamicCR
            sigmoid = settings.preferences.sigmoid
            adjustmentFactor = settings.preferences.adjustmentFactor
            weightPercentage = settings.preferences.weightPercentage
            averages = thirtyDaysAverages()
            aisf = settingsManager.settings.autoisf

            if unit == .mmolL {
                threshold_setting = settings.preferences.threshold_setting.asMmolL
            } else {
                threshold_setting = settings.preferences.threshold_setting
            }
        }

        var unChanged: Bool {
            preferences.enableDynamicCR == enableDynamicCR &&
                preferences.adjustmentFactor == adjustmentFactor &&
                preferences.sigmoid == sigmoid &&
                preferences.threshold_setting == convertBack(threshold_setting) &&
                preferences.useNewFormula == useNewFormula &&
                preferences.weightPercentage == weightPercentage
        }

        func convertBack(_ glucose: Decimal) -> Decimal {
            if unit == .mmolL {
                return glucose.asMgdL
            }
            return glucose
        }

        func saveIfChanged() {
            if !unChanged {
                var newSettings = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()
                newSettings.enableDynamicCR = enableDynamicCR
                newSettings.adjustmentFactor = adjustmentFactor
                newSettings.sigmoid = sigmoid
                newSettings.threshold_setting = convertBack(threshold_setting)
                newSettings.useNewFormula = useNewFormula
                newSettings.weightPercentage = weightPercentage
                newSettings.timestamp = Date()
                storage.save(newSettings, as: OpenAPS.Settings.preferences)
            }
        }

        var reasons: [Reasons] {
            CoreDataStorage().fetchReasons(interval: DateFilter().month)
        }

        private var sameUnit: Bool {
            unit == .mmolL
        }

        private func thirtyDaysAverages() -> (isf: Double, cr: Double, days: Double)? {
            let history = reasons.filter({ $0.mmol == sameUnit }).sorted(by: { $0.date ?? Date() > $1.date ?? Date() })
            let days = -1 * (history.last?.date ?? .now).timeIntervalSince(history.first?.date ?? .now) / 8.64E4
            // Avoid displaying "0 days"
            guard !history.isEmpty, days >= 0.06 else { return nil }

            let isf = history.compactMap(\.isf)
            let cr = history.compactMap(\.cr)
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
