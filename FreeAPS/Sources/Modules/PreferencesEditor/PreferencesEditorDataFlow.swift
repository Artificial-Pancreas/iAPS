import Foundation

enum PreferencesEditor {
    enum Config {}

    class Field<T>: Identifiable {
        var displayName: String
        var keypath: WritableKeyPath<Preferences, T>
        var infoText: String
        var value: T {
            didSet {
                settable?.onSet(keypath, value: value)
            }
        }

        weak var settable: PreferencesSettable?

        init(
            displayName: String,
            keypath: WritableKeyPath<Preferences, T>,
            value: T,
            infoText: String,
            settable: PreferencesSettable? = nil
        ) {
            self.displayName = displayName
            self.keypath = keypath
            self.value = value
            self.infoText = infoText
            self.settable = settable
        }

        let id = UUID()
    }
}

protocol PreferencesEditorProvider: Provider {
    var preferences: Preferences { get }
    func savePreferences(_ preferences: Preferences)
    func migrateUnits()
}

protocol PreferencesSettable: AnyObject {
    func onSet<T>(_ keypath: WritableKeyPath<Preferences, T>, value: T)
}
