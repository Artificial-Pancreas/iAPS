import Combine

extension CREditor {
    final class Provider: BaseProvider, CREditorProvider {
        var profile: CarbRatios {
            storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
                ?? (try? CarbRatios.decodeFrom(json: OpenAPS.defaults(for: OpenAPS.Settings.carbRatios)))
                ?? CarbRatios(units: .grams, schedule: [])
        }

        func saveProfile(_ profile: CarbRatios) {
            storage.save(profile, as: OpenAPS.Settings.carbRatios)
        }

        var autotune: Autotune? {
            storage.retrieve(OpenAPS.Settings.autotune, as: Autotune.self)
        }
    }
}
