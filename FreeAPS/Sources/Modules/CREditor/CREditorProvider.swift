import Combine

extension CREditor {
    final class Provider: BaseProvider, CREditorProvider {
        var profile: CarbRatios {
            (try? storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self))
                ?? CarbRatios(from: OpenAPS.defaults(for: OpenAPS.Settings.carbRatios))
                ?? CarbRatios(units: .grams, schedule: [CarbRatioEntry(start: "00:00:00", offset: 0, ratio: 10)])
        }

        func saveProfile(_ profile: CarbRatios) {
            try? storage.save(profile, as: OpenAPS.Settings.carbRatios)
        }
    }
}
