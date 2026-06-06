import AppIntents
import Foundation

struct ApplyTempPresetIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static let title: LocalizedStringResource = "Apply or cancel a temporary target Preset"

    // Description of the action in the Shortcuts app
    static let description = IntentDescription("Allow to apply or cancel a specific temporary target preset.")

    @Parameter(title: "Preset") var preset: TempPreset?

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
        let intent = TempPresetsIntentRequest()
        let presetToApply: TempPreset
        if let preset = preset {
            presetToApply = preset
        } else {
            presetToApply = try await $preset.requestDisambiguation(
                among: intent.fetchAll(),
                dialog: "Choose a temp preset."
            )
        }

        let displayName: String = presetToApply.name
        if confirmBeforeApplying {
            // deprecated, but the fix is iOS 18+ only
            try await requestConfirmation(
                result: .result(dialog: "Are you sure you want to apply the temp target \(displayName) ?")
            )
        }

        if presetToApply.duration == 0 {
            try await intent.cancelTempTarget()
            let displayDetail: String =
                "Temp Target Canceled"
            return .result(
                dialog: IntentDialog(stringLiteral: displayDetail)
            )
        } else {
            let tempTarget = try await intent.findTempTarget(presetToApply)
            let finalTempTargetApply = try await intent.enactTempTarget(tempTarget)
            let displayDetail: String =
                "the target \(finalTempTargetApply.displayName) is applying during \(finalTempTargetApply.duration) min"
            return .result(
                dialog: IntentDialog(stringLiteral: displayDetail)
            )
        }
    }
}
