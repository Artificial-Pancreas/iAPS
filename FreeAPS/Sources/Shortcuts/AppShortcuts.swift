import AppIntents
import Foundation

struct AppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ApplyTempPresetIntent(),
            phrases: [
                "Activate \(.applicationName) temporary target",
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
        AppShortcut(
            intent: ApplyOverrideIntent(),
            phrases: [
                "Activate an \(.applicationName) Override Preset",
                "Activates an \(.applicationName) Override Preset"
            ]
        )
        AppShortcut(
            intent: CancelOverrideIntent(),
            phrases: [
                "Cancel \(.applicationName) Overide",
                "Cancels an active \(.applicationName) override"
            ]
        )
        AppShortcut(
            intent: BolusIntent(),
            phrases: [
                "\(.applicationName) Bolus",
                "\(.applicationName) Enacts a bolus"
            ]
        )
        AppShortcut(
            intent: ApplyMealPresetIntent(),
            phrases: [
                "\(.applicationName) Meal Presets",
                "Uses an \(.applicationName) Meal Preset"
            ]
        )
        AppShortcut(
            intent: ModeIntent(),
            phrases: [
                "\(.applicationName) Loop Mode",
                "Activates an \(.applicationName) Loop Mode"
            ]
        )
        AppShortcut(
            intent: BasalIntent(),
            phrases: [
                "\(.applicationName) Temp Basal",
                "Enacts an \(.applicationName) Temp Basal"
            ]
        )
        AppShortcut(
            intent: SuspendResumeIntent(),
            phrases: [
                "\(.applicationName) Suspend/Resume",
                "Suspends/Resumes your \(.applicationName) pump"
            ]
        )
    }
}
