import AppIntents
import Foundation
import Intents

struct SuspendResumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Pump Mode"
    static var description = IntentDescription("Suspend or Resume Pump.")

    @Parameter(title: "Mode") var mode: String?

    @Parameter(
        title: "Confirm Before activating",
        description: "If toggled, you will need to confirm before activating",
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\SuspendResumeIntent.$confirmBeforeApplying, .equalTo, true, {
            Summary("Applying \(\.$mode)") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Immediately applying \(\.$mode)") {
                \.$confirmBeforeApplying
            }
        })
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let modeToApply: String

            modeToApply = try await $mode.requestDisambiguation(
                among: whichMode(),
                dialog: "Choose what to do with your pump"
            )

            let displayName: String = modeToApply
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(dialog: "Are you sure you want to \(displayName) your pump?")
                )
            }

            let confirmation = try SuspendResumeIntentRequest().setMode(modeToApply)
            return .result(
                dialog: IntentDialog(stringLiteral: confirmation)
            )
        } catch {
            throw error
        }
    }

    private func whichMode() -> [String] {
        [NSLocalizedString(PumpMode.suspend.rawValue, comment: ""), NSLocalizedString(PumpMode.resume.rawValue, comment: "")]
    }
}

final class SuspendResumeIntentRequest: BaseIntentsRequest {
    func setMode(_ mode: String) throws -> String {
        let resultDisplay: String =
            NSLocalizedString("Pump command", comment: "") + " \(mode)" + NSLocalizedString("enacted in iAPS", comment: "")
        if mode == PumpMode.resume.rawValue {
            apsManager.enactAnnouncement(Announcement(createdAt: Date(), enteredBy: "remote", notes: "pump:resume"))
        } else if mode == PumpMode.suspend.rawValue {
            apsManager.enactAnnouncement(Announcement(createdAt: Date(), enteredBy: "remote", notes: "pump:suspend"))
        }
        return resultDisplay
    }
}

enum PumpMode: String {
    case suspend = "Suspend"
    case resume = "Resume"
}
