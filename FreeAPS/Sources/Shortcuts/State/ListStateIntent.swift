import AppIntents
import Foundation

struct ListStateIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static let title: LocalizedStringResource = "List last state available with iAPS"

    // Description of the action in the Shortcuts app
    static let description = IntentDescription(
        "Allow to list the last Blood Glucose, trends, IOB and COB available in iAPS"
    )

    static var parameterSummary: some ParameterSummary {
        Summary("List all states of iAPS")
    }

    @MainActor func perform() async throws -> some ReturnsValue<StateiAPSResults> & ShowsSnippetView {
        let stateIntent = StateIntentRequest()
        let glucoseValues = try? await stateIntent.getLastBG()
        let iob_cob_value = try? await stateIntent.getIOB_COB()

        guard let glucoseValue = glucoseValues else { throw StateIntentError.NoBG }
        guard let iob_cob = iob_cob_value else { throw StateIntentError.NoIOBCOB }
        let settings = await stateIntent.settingsManager.settings
        let BG = StateiAPSResults(
            glucose: glucoseValue.glucose,
            trend: glucoseValue.trend,
            delta: glucoseValue.delta,
            date: glucoseValue.dateGlucose,
            iob: iob_cob.iob,
            cob: iob_cob.cob,
            unit: settings.units
        )
        return .result(
            value: BG,
            view: ListStateView(state: BG)
        )
    }
}
