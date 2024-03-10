import AppIntents
import Foundation
import Intents

@available(iOS 16.0,*) struct BolusIntent: AppIntent {
    static var title: LocalizedStringResource = "Bolus"
    static var description = IntentDescription("Allow to send a bolus command to iAPS.")

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
        do {
            let amount: Double
            if let cq = bolusQuantity {
                amount = cq
            } else {
                amount = try await $bolusQuantity.requestValue("Enter a Bolus Amount")
            }
            let bolusAmountString = amount.formatted()
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(dialog: "Are you sure you want to bolus \(bolusAmountString) U of insulin?")
                )
            }
            let finalQuantityBolusDisplay = try BolusIntentRequest().bolus(amount)
            return .result(
                dialog: IntentDialog(stringLiteral: finalQuantityBolusDisplay)
            )

        } catch {
            throw error
        }
    }
}

@available(iOS 16.0,*) final class BolusIntentRequest: BaseIntentsRequest {
    func bolus(_ bolusAmount: Double) throws -> String {
        guard bolusAmount >= Double(settingsManager.preferences.bolusIncrement) else {
            return "too small bolus amount"
        }
        let bolus = min(
            max(Decimal(bolusAmount), settingsManager.preferences.bolusIncrement),
            settingsManager.pumpSettings.maxBolus
        )
        let resultDisplay: String =
            "A bolus command of \(bolus) U of insulin was sent to iAPS. Verify in iAPS app or in Nightscout if the bolus was delivered."

        apsManager.enactBolus(amount: Double(bolus), isSMB: false)
        return resultDisplay
    }
}
