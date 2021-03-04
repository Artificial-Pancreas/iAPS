extension TargetsEditor {
    final class Provider: BaseProvider, TargetsEditorProvider {
        var profile: BGTargets {
            (try? storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self))
                ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
                ?? BGTargets(units: .mmolL, userPrefferedUnits: .mmolL, targets: [])
        }

        func saveProfile(_ profile: BGTargets) {
            try? storage.save(profile, as: OpenAPS.Settings.bgTargets)
        }
    }
}
