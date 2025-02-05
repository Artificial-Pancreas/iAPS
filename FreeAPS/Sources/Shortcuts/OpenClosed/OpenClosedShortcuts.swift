import AppIntents
import Foundation
import Intents

struct ModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Loop Mode"
    static var description = IntentDescription("Activate Open or Closed Loop Mode.")

    @Parameter(title: "Mode") var mode: String?

    @Parameter(
        title: "Confirm Before activating",
        description: "If toggled, you will need to confirm before activating",
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\ModeIntent.$confirmBeforeApplying, .equalTo, true, {
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
                dialog: "Which Loop Mode would you like to activate?"
            )

            let displayName: String = modeToApply
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(dialog: "Are you sure you want to activate the Loop Mode \(displayName)?")
                )
            }

            let confirmation = try ModeIntentRequest().setMode(modeToApply)
            return .result(
                dialog: IntentDialog(stringLiteral: confirmation)
            )
        } catch {
            throw error
        }
    }

    func whichMode() -> [String] {
        [Mode.closed.rawValue, Mode.open.rawValue]
    }
}

final class ModeIntentRequest: BaseIntentsRequest {
    func setMode(_ mode: String) throws -> String {
        let resultDisplay: String =
            NSLocalizedString("The Loop Mode", comment: "") + " \(mode) " +
            NSLocalizedString("is now activated", comment: "")

        if mode == Mode.closed.rawValue {
            apsManager.enactAnnouncement(Announcement(createdAt: Date(), enteredBy: "remote", notes: "looping:true"))
        } else if mode == Mode.open.rawValue {
            apsManager.enactAnnouncement(Announcement(createdAt: Date(), enteredBy: "remote", notes: "looping:false"))
        }
        return resultDisplay
    }
}

enum Mode: String {
    case closed = "Closed"
    case open = "Open"
}
