import AppIntents
import Foundation
import Intents

struct BasalIntent: AppIntent {
    static var title: LocalizedStringResource = "Temp Basal"
    static var description = IntentDescription("Allow to enact a temp basal command to iAPS.")

    @Parameter(
        title: "Amount",
        description: "Temp basal Amount in U/h",
        controlStyle: .field,
        inclusiveRange: (lowerBound: 0.05, upperBound: 10),
        requestValueDialog: IntentDialog("What is the numeric value of the basal amount in insulin units")
    ) var basalQuantity: Double?

    @Parameter(
        title: "Confirm Before applying",
        description: "If toggled, you will need to confirm before applying",
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$confirmBeforeApplying, .equalTo, true, {
            Summary("Applying \(\.$basalQuantity)") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Immediately applying \(\.$basalQuantity)") {
                \.$confirmBeforeApplying
            }
        })
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let amount: Double
            if let quantity = basalQuantity {
                amount = quantity
            } else {
                amount = try await $basalQuantity.requestValue("Enter a Basal Amount")
            }
            let basalAmountString = amount.formatted()

            if confirmBeforeApplying {
                let glucoseString = BolusIntentRequest().currentGlucose() // Fetch current glucose
                try await requestConfirmation(
                    result: .result(
                        dialog: "Your current glucose is \(glucoseString != nil ? glucoseString! : "not available"). Are you sure you want to enact a temp basal \(basalAmountString) U/h for 60 minutes?"
                    )
                )
            }
            let finalQuantityBasalDisplay = try BasalIntentRequest().basal(amount)
            return .result(
                dialog: IntentDialog(stringLiteral: finalQuantityBasalDisplay)
            )

        } catch {
            throw error
        }
    }
}

final class BasalIntentRequest: BaseIntentsRequest {
    func basal(_ basalAmount: Double) throws -> String {
        guard !settingsManager.settings.closedLoop else {
            return NSLocalizedString("Basal Shortcuts are disabled because iAPS is in cLosed loop mode", comment: "")
        }
        guard basalAmount >= Double(settingsManager.preferences.bolusIncrement) else {
            return NSLocalizedString("too small temp basal amount", comment: "")
        }

        guard basalAmount <= Double(settingsManager.pumpSettings.maxBasal) else {
            return NSLocalizedString("Max Basal exceeded!", comment: "")
        }

        let basal = min(
            max(Decimal(basalAmount), settingsManager.preferences.bolusIncrement),
            settingsManager.pumpSettings.maxBasal
        )

        let resultDisplay: String =
            NSLocalizedString("A temp basal command of ", comment: "") + basal.formatted() + NSLocalizedString(
                " U/h for 60 minutes was sent to iAPS. Verify in iAPS app or in Nightscout that the temp basal was enacted.",
                comment: ""
            )

        apsManager.enactTempBasal(rate: Double(basal), duration: 1.8E3)
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
