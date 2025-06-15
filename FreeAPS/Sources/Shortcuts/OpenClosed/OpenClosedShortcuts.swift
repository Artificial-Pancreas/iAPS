import AppIntents
import Foundation
import Intents

struct ModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Loop Mode"
    static var description = IntentDescription("Activate Open or Closed Loop Mode.")
    @Parameter(title: "Loop Mode") var mode: Mode?

    @Parameter(
        title: "Confirm Before activating",
        description: "If toggled, you will need to confirm before activating",
        default: false
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
            let modeToApply: Mode
            if let selection = mode {
                modeToApply = selection
            } else {
                modeToApply = try await $mode.requestDisambiguation(
                    among: whichMode(),
                    dialog: "Select Loop Mode"
                )
            }

            let displayName: String = modeToApply.rawValue
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

    func whichMode() -> [Mode] {
        [Mode.closed, Mode.open]
    }
}

final class ModeIntentRequest: BaseIntentsRequest {
    func setMode(_ mode: Mode) throws -> String {
        let resultDisplay: String =
            NSLocalizedString("The Loop Mode", comment: "") + " \(mode.rawValue) " +
            NSLocalizedString("is now activated", comment: "")

        if mode == Mode.closed {
            apsManager.enactAnnouncement(Announcement(createdAt: Date(), enteredBy: "remote", notes: "looping:true"))
        } else if mode == Mode.open {
            apsManager.enactAnnouncement(Announcement(createdAt: Date(), enteredBy: "remote", notes: "looping:false"))
        }
        return resultDisplay
    }
}

enum Mode: String {
    case closed = "Closed"
    case open = "Open"
}

extension Mode: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Mode"

    static var caseDisplayRepresentations: [Mode: DisplayRepresentation] = [
        .closed: "Closed",
        .open: "Open"
    ]
}
