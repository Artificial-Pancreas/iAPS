extension ISFEditor {
    final class Provider: BaseProvider, ISFEditorProvider {
        var profile: InsulinSensitivities {
            (try? storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self))
                ?? InsulinSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.insulinSensitivities))
                ?? InsulinSensitivities(
                    units: .mmolL,
                    userPrefferedUnits: .mmolL,
                    sensitivities: [InsulinSensitivityEntry(sensitivity: 3.0, offset: 0, start: "00:00:00")]
                )
        }

        func saveProfile(_ profile: InsulinSensitivities) {
            try? storage.save(profile, as: OpenAPS.Settings.insulinSensitivities)
        }
    }
}
