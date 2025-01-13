import Foundation
import LoopKit

protocol SettableValue {}
extension Bool: SettableValue {}
extension Decimal: SettableValue {}
extension InsulinCurve: SettableValue {}

enum PreferencesEditor {
    enum Config {}

    enum FieldType {
        case boolean(keypath: WritableKeyPath<Preferences, Bool>)
        case decimal(keypath: WritableKeyPath<Preferences, Decimal>)
        case glucose(keypath: WritableKeyPath<Preferences, Decimal>)
        case insulinCurve(keypath: WritableKeyPath<Preferences, InsulinCurve>)
    }

    class Field: Identifiable {
        var displayName: String
        var type: FieldType
        var infoText: String

        var boolValue: Bool {
            get {
                switch type {
                case let .boolean(keypath):
                    return settable?.get(keypath) ?? false
                default: return false
                }
            }
            set { set(value: newValue) }
        }

        var decimalValue: Decimal {
            get {
                switch type {
                case let .decimal(keypath):
                    return settable?.get(keypath) ?? 0
                case let .glucose(keypath):
                    return settable?.get(keypath) ?? 0
                default: return 0
                }
            }
            set { set(value: newValue) }
        }

        var insulinCurveValue: InsulinCurve {
            get {
                switch type {
                case let .insulinCurve(keypath):
                    return settable?.get(keypath) ?? .rapidActing
                default: return .rapidActing
                }
            }
            set { set(value: newValue) }
        }

        private func set<T: SettableValue>(value: T) {
            switch (type, value) {
            case let (.boolean(keypath), value as Bool):
                settable?.set(keypath, value: value)
            case let (.decimal(keypath), value as Decimal):
                settable?.set(keypath, value: value)
            case let (.glucose(keypath), value as Decimal):
                settable?.set(keypath, value: value)
            case let (.insulinCurve(keypath), value as InsulinCurve):
                settable?.set(keypath, value: value)
            default: break
            }
        }

        weak var settable: PreferencesSettable?

        init(
            displayName: String,
            type: FieldType,
            infoText: String,
            settable: PreferencesSettable? = nil
        ) {
            self.displayName = displayName
            self.type = type
            self.infoText = infoText
            self.settable = settable
        }

        let id = UUID()
    }

    struct FieldSection: Identifiable {
        let displayName: String
        var fields: [Field]
        let id = UUID()
    }
}

protocol PreferencesEditorProvider: Provider {
    var preferences: Preferences { get }
    func savePreferences(_ preferences: Preferences)
    func migrateUnits()
}

protocol PreferencesSettable: AnyObject {
    func set<T>(_ keypath: WritableKeyPath<Preferences, T>, value: T)
    func get<T>(_ keypath: WritableKeyPath<Preferences, T>) -> T
}
