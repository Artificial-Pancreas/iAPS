import AppIntents
import Foundation

struct AppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ApplyTempPresetIntent(), phrases: [
            "Activate \(.applicationName) temporary target",
            "\(.applicationName) apply a temporary target"
        ], shortTitle: "Temorary Target", systemImageName: "scope")
        AppShortcut(
            intent: ListStateIntent(),
            phrases: [
                "List \(.applicationName) state",
                "\(.applicationName) state"
            ], shortTitle: "List state", systemImageName: "list.bullet.rectangle.portrait"
        )
        AppShortcut(
            intent: AddCarbPresentIntent(),
            phrases: [
                "Add carbs in \(.applicationName)",
                "\(.applicationName) allows to add carbs"
            ], shortTitle: "Carbs", systemImageName: "carrot.fill"
        )
        AppShortcut(
            intent: ApplyOverrideIntent(),
            phrases: [
                "Activate an \(.applicationName) Override Preset",
                "Activates an \(.applicationName) Override Preset"
            ], shortTitle: "Overrides", systemImageName: "figure.run"
        )
        AppShortcut(
            intent: CancelOverrideIntent(),
            phrases: [
                "Cancel \(.applicationName) Overide",
                "Cancels an active \(.applicationName) override"
            ], shortTitle: "Cancel override", systemImageName: "figure.stand"
        )
        AppShortcut(
            intent: BolusIntent(),
            phrases: [
                "\(.applicationName) Bolus",
                "\(.applicationName) Enacts a bolus"
            ], shortTitle: "Bolus", systemImageName: "syringe.fill"
        )
        AppShortcut(
            intent: ApplyMealPresetIntent(),
            phrases: [
                "\(.applicationName) Meal Presets",
                "Uses an \(.applicationName) Meal Preset"
            ], shortTitle: "Meal Preset", systemImageName: "menucard"
        )
        AppShortcut(
            intent: ModeIntent(),
            phrases: [
                "\(.applicationName) Loop Mode",
                "Activates an \(.applicationName) Loop Mode"
            ], shortTitle: "Loop Mode", systemImageName: "circle"
        )
        AppShortcut(
            intent: BasalIntent(),
            phrases: [
                "\(.applicationName) Temp Basal",
                "Enacts an \(.applicationName) Temp Basal"
            ], shortTitle: "Temp Basal", systemImageName: "syringe"
        )
        AppShortcut(
            intent: SuspendResumeIntent(),
            phrases: [
                "\(.applicationName) Suspend/Resume",
                "Suspends/Resumes your \(.applicationName) pump"
            ], shortTitle: "Suspend/Resume", systemImageName: "playpause"
        )
    }
}
