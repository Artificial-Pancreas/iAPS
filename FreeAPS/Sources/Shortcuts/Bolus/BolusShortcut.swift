import AppIntents
import Foundation
import Intents

struct BolusIntent: AppIntent {
    static let title: LocalizedStringResource = "Bolus"
    static let description = IntentDescription("Allow to send a bolus command to iAPS.")

    @Parameter(
        title: "Amount",
        description: "Bolus Amount in U",
        controlStyle: .field,
        inclusiveRange: (lowerBound: 0.05, upperBound: 10),
        requestValueDialog: IntentDialog("What is the numeric value of the bolus amount in insulin units")
    ) var bolusQuantity: Double?

    @Parameter(
        title: "Confirm Before applying",
        description: "If toggled, you will need to confirm before applying",
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$confirmBeforeApplying, .equalTo, true, {
            Summary("Applying \(\.$bolusQuantity)") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Immediately applying \(\.$bolusQuantity)") {
                \.$confirmBeforeApplying
            }
        })
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        let amount: Double
        if let quantity = bolusQuantity {
            amount = quantity
        } else {
            amount = try await $bolusQuantity.requestValue("Enter a Bolus Amount")
        }
        let bolusAmountString = amount.formatted()

        let bolusIntentRequest = BolusIntentRequest()

        if confirmBeforeApplying {
            let glucoseString = await bolusIntentRequest.currentGlucose() // Fetch current glucose
            // deprecated, but the fix is iOS 18+ only
            try await requestConfirmation(
                result: .result(
                    dialog: "Your current glucose is \(glucoseString ?? "not available"). Are you sure you want to bolus \(bolusAmountString) U of insulin?"
                )
            )
        }
        let finalQuantityBolusDisplay = try await bolusIntentRequest.bolus(amount)
        return .result(
            dialog: IntentDialog(stringLiteral: finalQuantityBolusDisplay)
        )
    }
}

final class BolusIntentRequest: BaseIntentsRequest {
    func bolus(_ bolusAmount: Double) async throws -> String {
        let settings = await settingsManager.settings
        let preferences = await settingsManager.preferences
        let pumpSettings = await settingsManager.pumpSettings

        guard settings.allowBolusShortcut else {
            return NSLocalizedString("Bolus Shortcuts are disabled in iAPS settings", comment: "")
        }
        guard bolusAmount >= Double(preferences.bolusIncrement) else {
            return NSLocalizedString("too small bolus amount", comment: "")
        }

        guard bolusAmount <= Double(pumpSettings.maxBolus),
              settings.allowedRemoteBolusAmount >= Decimal(bolusAmount)
        else {
            return NSLocalizedString("Max Bolus exceeded!", comment: "")
        }

        let bolus = min(
            max(Decimal(bolusAmount), preferences.bolusIncrement),
            pumpSettings.maxBolus, settings.allowedRemoteBolusAmount
        )

        let resultDisplay: String =
            NSLocalizedString("A bolus command of ", comment: "") + bolus.formatted() + NSLocalizedString(
                " U of insulin was sent to iAPS. Verify in iAPS app or in Nightscout if the bolus was delivered.",
                comment: ""
            )

        Task { [apsManager] in
            _ = await apsManager?.enactBolus(amount: Double(bolus), isSMB: false)
        }
        return resultDisplay
    }

    func currentGlucose() async -> String? {
        let settings = await settingsManager.settings

        if let fetchedReading = await coreDataStorage.fetchGlucose(interval: DateFilter.today.startDate).first {
            let fetchedGlucose = Decimal(fetchedReading.glucose)
            let convertedString = settings.units == .mmolL ? fetchedGlucose.asMmolL
                .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) : fetchedGlucose
                .formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))

            return convertedString + " " + NSLocalizedString(settings.units.rawValue, comment: "Glucose Unit")
        }
        return nil
    }
}
