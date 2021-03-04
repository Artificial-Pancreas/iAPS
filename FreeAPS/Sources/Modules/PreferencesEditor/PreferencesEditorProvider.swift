import Foundation

extension PreferencesEditor {
    final class Provider: BaseProvider, PreferencesEditorProvider {
        private let processQueue = DispatchQueue(label: "PreferencesEditorProvider.processQueue")
        var preferences: Preferences {
            (try? storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self))
                ?? Preferences(from: OpenAPS.defaults(for: OpenAPS.Settings.preferences))
                ?? Preferences()
        }

        func savePreferences(_ preferences: Preferences) {
            processQueue.async {
                try? self.storage.save(preferences, as: OpenAPS.Settings.preferences)
            }
        }
    }
}
