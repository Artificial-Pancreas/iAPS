import AppIntents
import Foundation

struct ApplyTempPresetIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title: LocalizedStringResource = "Apply a temporary Preset"

    // Description of the action in the Shortcuts app
    static var description = IntentDescription("Allow to apply a specific temporary preset.")

    internal var intentRequest: TempPresetsIntentRequest

    init() {
        intentRequest = TempPresetsIntentRequest()
    }

    @Parameter(title: "Preset") var preset: tempPreset?

    @Parameter(
        title: "Confirm Before applying",
        description: "If toggled, you will need to confirm before applying",
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\ApplyTempPresetIntent.$confirmBeforeApplying, .equalTo, true, {
            Summary("Applying \(\.$preset)") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Immediately applying \(\.$preset)") {
                \.$confirmBeforeApplying
            }
        })
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let presetToApply: tempPreset
            if let preset = preset {
                presetToApply = preset
            } else {
                presetToApply = try await $preset.requestDisambiguation(
                    among: intentRequest.fetchAll(),
                    dialog: "What temp preset would you like ?"
                )
            }

            let displayName: String = presetToApply.name
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(dialog: "Are you sure to applying the temp target \(displayName) ?")
                )
            }

            // TODO: enact the temp target
            let tempTarget = try intentRequest.findTempTarget(presetToApply)
            let finalTempTargetApply = try intentRequest.enactTempTarget(tempTarget)
            let displayDetail: String =
                "the target \(finalTempTargetApply.displayName) is applying during \(finalTempTargetApply.duration) mn"
            return .result(
                dialog: IntentDialog(stringLiteral: displayDetail)
            )
        } catch {
            throw error
        }
    }
}
