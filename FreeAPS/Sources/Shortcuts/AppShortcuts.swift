import AppIntents
import Foundation

@available(iOS 16.0, *) struct AppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ApplyTempPresetIntent(),
            phrases: [
                "Activate \(.applicationName) temporary target ?",
                "\(.applicationName) apply a temporary target"
            ]
        )
        AppShortcut(
            intent: ListStateIntent(),
            phrases: [
                "List \(.applicationName) state",
                "\(.applicationName) state"
            ]
        )
        AppShortcut(
            intent: AddCarbPresentIntent(),
            phrases: [
                "Add carbs in \(.applicationName)",
                "\(.applicationName) allows to add carbs"
            ]
        )
    }
}
