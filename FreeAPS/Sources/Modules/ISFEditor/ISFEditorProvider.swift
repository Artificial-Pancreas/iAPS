extension ISFEditor {
    final class Provider: BaseProvider, ISFEditorProvider {
        var profile: InsulinSensitivities {
            (try? storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self))
                ?? InsulinSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.insulinSensitivities))
                ?? InsulinSensitivities(
                    units: .mmolL,
                    userPrefferedUnits: .mmolL,
                    sensitivities: []
                )
        }

        func saveProfile(_ profile: InsulinSensitivities) {
            try? storage.save(profile, as: OpenAPS.Settings.insulinSensitivities)
        }

        var autosense: Autosens {
            (try? storage.retrieve(OpenAPS.Settings.autosense, as: Autosens.self))
                ?? Autosens(from: OpenAPS.defaults(for: OpenAPS.Settings.autosense))
                ?? Autosens(ratio: 1, newisf: nil, timestamp: nil)
        }
    }
}
