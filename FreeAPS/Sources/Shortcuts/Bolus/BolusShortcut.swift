import AppIntents
import Foundation
import Intents

struct BolusIntent: AppIntent {
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
            if let quantity = bolusQuantity {
                amount = quantity
            } else {
                amount = try await $bolusQuantity.requestValue("Enter a Bolus Amount")
            }
            let bolusAmountString = amount.formatted()

            if confirmBeforeApplying {
                let glucoseString = BolusIntentRequest().currentGlucose() // Fetch current glucose
                try await requestConfirmation(
                    result: .result(
                        dialog: "Your current glucose is \(glucoseString != nil ? glucoseString! : "not available"). Are you sure you want to bolus \(bolusAmountString) U of insulin?"
                    )
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

final class BolusIntentRequest: BaseIntentsRequest {
    func bolus(_ bolusAmount: Double) throws -> String {
        guard settingsManager.settings.allowBolusShortcut else {
            return NSLocalizedString("Bolus Shortcuts are disabled in iAPS settings", comment: "")
        }
        guard bolusAmount >= Double(settingsManager.preferences.bolusIncrement) else {
            return NSLocalizedString("too small bolus amount", comment: "")
        }

        guard bolusAmount <= Double(settingsManager.pumpSettings.maxBolus),
              settingsManager.settings.allowedRemoteBolusAmount >= Decimal(bolusAmount)
        else {
            return NSLocalizedString("Max Bolus exceeded!", comment: "")
        }

        let bolus = min(
            max(Decimal(bolusAmount), settingsManager.preferences.bolusIncrement),
            settingsManager.pumpSettings.maxBolus, settingsManager.settings.allowedRemoteBolusAmount
        )

        let resultDisplay: String =
            NSLocalizedString("A bolus command of ", comment: "") + bolus.formatted() + NSLocalizedString(
                " U of insulin was sent to iAPS. Verify in iAPS app or in Nightscout if the bolus was delivered.",
                comment: ""
            )

        apsManager.enactBolus(amount: Double(bolus), isSMB: false)
        return resultDisplay
    }

    func currentGlucose() -> String? {
        if let fetchedReading = coreDataStorage.fetchGlucose(interval: DateFilter().today).first {
            let fetchedGlucose = Decimal(fetchedReading.glucose)
            let convertedString = settingsManager.settings.units == .mmolL ? fetchedGlucose.asMmolL
                .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) : fetchedGlucose
                .formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))

            return convertedString + " " + NSLocalizedString(settingsManager.settings.units.rawValue, comment: "Glucose Unit")
        }
        return nil
    }
}
