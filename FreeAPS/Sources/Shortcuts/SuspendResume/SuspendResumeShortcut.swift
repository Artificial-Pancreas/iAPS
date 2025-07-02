import AppIntents
import Foundation
import Intents

struct SuspendResumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Pump Mode"
    static var description = IntentDescription("Suspend or Resume Pump.")

    @Parameter(title: "Mode") var mode: PumpMode?

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
            let modeToApply: PumpMode
            if let selection = mode {
                modeToApply = selection
            } else {
                modeToApply = try await $mode.requestDisambiguation(
                    among: whichMode(),
                    dialog: "Choose what to do with your pump"
                )
            }

            let displayName: String = modeToApply.rawValue
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(dialog: "Are you sure you want to \(displayName)?")
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

    func whichMode() -> [PumpMode] {
        [PumpMode.suspend, PumpMode.resume, PumpMode.cancel]
    }
}

final class SuspendResumeIntentRequest: BaseIntentsRequest {
    func setMode(_ mode: PumpMode) throws -> String {
        let resultDisplay: String =
            NSLocalizedString("Pump command", comment: "") + " \(mode) " + NSLocalizedString("enacted in iAPS", comment: "")
        if mode == PumpMode.resume {
            apsManager.enactAnnouncement(Announcement(createdAt: Date(), enteredBy: "remote", notes: "pump:resume"))
        } else if mode == PumpMode.suspend {
            apsManager.enactAnnouncement(Announcement(createdAt: Date(), enteredBy: "remote", notes: "pump:suspend"))
        } else if mode == PumpMode.cancel {
            apsManager.enactTempBasal(rate: 0, duration: 0)
        }
        return resultDisplay
    }
}

enum PumpMode: String {
    case suspend = "Suspend"
    case resume = "Resume"
    case cancel = "Cancel Temp"
}

extension PumpMode: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "PumpMode"

    static let caseDisplayRepresentations: [PumpMode: DisplayRepresentation] = [
        .suspend: "Suspend",
        .resume: "Resume",
        .cancel: "Cancel Temp"
    ]
}
