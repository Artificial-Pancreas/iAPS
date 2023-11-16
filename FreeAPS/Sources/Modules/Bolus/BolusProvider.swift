extension Bolus {
    final class Provider: BaseProvider, BolusProvider {
        let coreDataStorage = CoreDataStorage()

        var suggestion: Suggestion? {
            storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
        }

        func pumpSettings() -> PumpSettings {
            storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
                ?? PumpSettings(insulinActionCurve: 6, maxBolus: 10, maxBasal: 2)
        }

        func fetchGlucose() -> [Readings] {
            let fetchGlucose = coreDataStorage.fetchGlucose(interval: DateFilter().twoHours)
            return fetchGlucose
        }
    }
}
