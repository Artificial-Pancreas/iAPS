import Combine

extension CREditor {
    final class Provider: BaseProvider, CREditorProvider {
        var profile: CarbRatios {
            (try? storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self))
                ?? CarbRatios(from: OpenAPS.defaults(for: OpenAPS.Settings.carbRatios))
                ?? CarbRatios(units: .grams, schedule: [])
        }

        func saveProfile(_ profile: CarbRatios) {
            try? storage.save(profile, as: OpenAPS.Settings.carbRatios)
        }

        var autotune: Autotune? {
            try? storage.retrieve(OpenAPS.Settings.autotune, as: Autotune.self)
        }
    }
}
